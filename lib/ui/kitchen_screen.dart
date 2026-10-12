import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../application/kitchen_controller.dart';
import '../application/recipe_library_controller.dart';
import '../domain/kitchen_timer.dart';
import '../data/kitchen_timer_file_store.dart';
import '../platform/kitchen_device.dart';
import 'home_screen.dart';
import 'kitchen_scope.dart';
import 'recipe_theme.dart';
import 'recipe_section.dart';

enum _KitchenExitChoice { back, stop, continueTimers }

class KitchenScreen extends StatefulWidget {
  const KitchenScreen({
    required this.library,
    this.notificationTarget,
    this.timerStore,
    super.key,
  });
  final RecipeLibraryController library;
  final ValueNotifier<String?>? notificationTarget;
  final KitchenTimerFileStore? timerStore;

  @override
  State<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends State<KitchenScreen>
    with WidgetsBindingObserver {
  final _device = KitchenDevice();
  late final _kitchen = KitchenController(now: _device.now);
  final _navigator = GlobalKey<NavigatorState>();
  Timer? _ticker;
  bool _ready = false;
  bool _allowPop = false;
  bool _exiting = false;
  bool _saving = false;
  bool _loaded = false;
  Future<void>? _loading;
  KitchenTimerFileStore? _fileStore;
  KitchenTimerSnapshot? _rebootSnapshot;
  String? _bootId;
  int _lifecycleGeneration = 0;
  String? _error;
  String? _notificationWarning;
  String? _notificationTargetId;
  String? _selectedTimerId;
  static const _background = RecipeTheme.cream;
  static const _accent = RecipeTheme.forest;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notificationTargetId = widget.notificationTarget?.value;
    widget.notificationTarget?.addListener(_notificationTargetChanged);
    _kitchen.open(foreground: false);
    _applyLifecycle(
      WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _applyLifecycle(state);
  }

  Future<void> _applyLifecycle(AppLifecycleState state) async {
    final generation = ++_lifecycleGeneration;
    _ticker?.cancel();
    _kitchen.setForeground(false);
    if (mounted) setState(() => _ready = false);
    try {
      await _device.setAwake(false);
      if (state != AppLifecycleState.resumed || _exiting) return;
      await _device.synchronizeClock();
      if (!mounted || generation != _lifecycleGeneration || _exiting) return;
      await _loadTimers();
      if (!mounted || generation != _lifecycleGeneration || _exiting) return;
      await _syncNotifications();
      if (!mounted || generation != _lifecycleGeneration || _exiting) return;
      _kitchen.setForeground(true);
      await _device.setAwake(_kitchen.shouldKeepAwake);
      if (!mounted || generation != _lifecycleGeneration || _exiting) return;
      setState(() {
        _ready = _rebootSnapshot == null;
        _error = null;
      });
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!_ready || _saving || _exiting) return;
        final now = _device.now();
        if (_kitchen.timers.any(
          (t) => t.state == KitchenTimerState.running && now >= t.deadline!,
        )) {
          _perform((k) => k.refresh());
        } else {
          _kitchen.refreshDisplay();
        }
      });
    } catch (_) {
      // Native lifecycle independently clears the flag when the Activity hides.
      await _device.setAwake(false).catchError((Object _) {});
      if (mounted && generation == _lifecycleGeneration) {
        _kitchen.setForeground(false);
        setState(
          () => _error = '時計またはタイマーの保存を読み込めませんでした。保存データは変更していません。再試行してください。',
        );
      }
    }
  }

  Future<void> _loadTimers() async {
    if (_loaded) return;
    if (_loading != null) return _loading!;
    final loading = _readTimers();
    _loading = loading;
    try {
      await loading;
    } finally {
      _loading = null;
    }
  }

  Future<void> _readTimers() async {
    _bootId = await _device.bootId();
    if (widget.timerStore != null) {
      _fileStore = widget.timerStore;
    } else {
      final directory = await getApplicationSupportDirectory();
      _fileStore = KitchenTimerFileStore(
        File('${directory.path}/kitchen-timers-v1.json'),
      );
    }
    final snapshot = await _fileStore!.load();
    if (!mounted) return;
    if (snapshot != null) {
      if (snapshot.requiresRebootReview(_bootId!)) {
        _rebootSnapshot = snapshot;
      } else {
        final timers = snapshot.restore(
          currentBootId: _bootId!,
          now: _device.now(),
        );
        if (timers.asMap().entries.any(
          (e) => !identical(e.value, snapshot.timers[e.key]),
        )) {
          await _saveTimers(timers);
        }
        if (!mounted) return;
        _kitchen.restoreTimers(timers);
        if (timers.isNotEmpty) {
          _selectedTimerId = _notificationTargetId ?? timers.first.id;
        }
      }
    }
    _loaded = true;
  }

  Future<void> _saveTimers(List<KitchenTimer> timers) =>
      _fileStore!.save(KitchenTimerSnapshot(bootId: _bootId!, timers: timers));

  Future<KitchenNotificationStatus?> _syncNotifications() async {
    try {
      final status = await _device.syncTimerNotifications(_kitchen.timers);
      if (mounted) {
        setState(() {
          _notificationWarning = status.warning;
        });
      }
      return status;
    } catch (_) {
      if (mounted) {
        setState(
          () => _notificationWarning = 'Androidの終了通知を同期できません。画面内タイマーは利用できます。',
        );
      }
      return null;
    }
  }

  Future<bool> _perform(void Function(KitchenController) operation) async {
    if (_saving) return false;
    setState(() => _saving = true);
    _kitchen.refreshDisplay();
    try {
      await _kitchen.transact(operation, _saveTimers);
      await _syncNotifications();
      return true;
    } catch (_) {
      _ticker?.cancel();
      if (mounted) {
        setState(() {
          _ready = false;
          _error = 'タイマーを保存できませんでした。操作を反映していません。再試行してください。';
        });
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        _kitchen.refreshDisplay();
      }
    }
  }

  Future<void> _reviewReboot() async {
    final snapshot = _rebootSnapshot;
    if (snapshot == null || _saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('端末再起動後のタイマー'),
        content: SingleChildScrollView(
          child: Text(
            '計測中だったタイマーは停止として復元します。必要な時間を確認してから開始してください。\n\n${snapshot.timers.map((t) => t.name).join('\n')}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('停止して復元'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final restored = await _perform(
      (k) => k.restoreTimers(
        snapshot.timers.map((t) => t.stopAfterReboot(now: _device.now())),
      ),
    );
    if (restored && mounted) {
      setState(() {
        _rebootSnapshot = null;
        _ready = true;
      });
    }
  }

  @override
  void dispose() {
    ++_lifecycleGeneration;
    WidgetsBinding.instance.removeObserver(this);
    widget.notificationTarget?.removeListener(_notificationTargetChanged);
    _ticker?.cancel();
    unawaited(_device.setAwake(false).catchError((Object _) {}));
    _kitchen.dispose();
    super.dispose();
  }

  void _notificationTargetChanged() {
    if (!mounted) return;
    setState(() {
      _notificationTargetId = widget.notificationTarget?.value;
      if (_notificationTargetId != null) {
        _selectedTimerId = _notificationTargetId;
      }
    });
  }

  Future<void> _back() async {
    if (_exiting) return;
    if (_navigator.currentState?.canPop() ?? false) {
      await _navigator.currentState!.maybePop();
    } else {
      await _exit();
    }
  }

  Future<bool> _configureNotifications() async {
    var status = await _device.notificationStatus();
    if (!status.readyForBackground) {
      if (!mounted) return false;
      final configure = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('画面を閉じた後も知らせる'),
          content: const Text(
            'タイマーを続けてキッチンを閉じるには、Androidの通知と「アラームとリマインダー」を許可してください。'
            '端末のサイレント設定、音量0、電池制限、強制停止中は音や定刻配送を保証できません。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('戻る'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('設定する'),
            ),
          ],
        ),
      );
      if (configure != true || !mounted) return false;
    }

    if (!status.notificationPermission) {
      await _device.requestNotificationPermission();
      status = await _device.notificationStatus();
      if (!status.notificationPermission) {
        await _device.openNotificationSettings();
        if (mounted) {
          setState(
            () => _notificationWarning = '通知を許可してから、もう一度「タイマーを続けて終了」を選んでください。',
          );
        }
        return false;
      }
    }
    if (!status.channelEnabled) {
      await _device.openNotificationSettings();
      if (mounted) {
        setState(
          () => _notificationWarning = 'キッチンタイマーの通知を有効にしてから、もう一度お試しください。',
        );
      }
      return false;
    }
    if (!status.exactAlarmAllowed) {
      await _device.openExactAlarmSettings();
      if (mounted) {
        setState(
          () => _notificationWarning = '「アラームとリマインダー」を許可してから、もう一度お試しください。',
        );
      }
      return false;
    }
    final synced = await _syncNotifications();
    return synced?.readyForBackground == true;
  }

  Future<void> _exit() async {
    if (_exiting || _saving) return;
    _exiting = true;
    var closeMode = KitchenCloseMode.requireInactive;
    if (_kitchen.hasActiveTimers) {
      final choice = await showDialog<_KitchenExitChoice>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('動作中のタイマーがあります'),
          content: const Text(
            '続けて終了すると、Androidの通知・音・振動で終了を知らせます。'
            '停止して終了すると、後から通知しません。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, _KitchenExitChoice.back),
              child: const Text('戻る'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, _KitchenExitChoice.stop),
              child: const Text('停止して終了'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, _KitchenExitChoice.continueTimers),
              child: const Text('タイマーを続けて終了'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (choice == null || choice == _KitchenExitChoice.back) {
        _exiting = false;
        await _applyLifecycle(
          WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed,
        );
        return;
      }
      if (choice == _KitchenExitChoice.continueTimers) {
        if (!await _configureNotifications()) {
          _exiting = false;
          await _applyLifecycle(
            WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed,
          );
          return;
        }
        closeMode = KitchenCloseMode.continueTimers;
      } else {
        closeMode = KitchenCloseMode.stopTimers;
      }
    }
    ++_lifecycleGeneration;
    _ticker?.cancel();
    if (!await _perform((k) => k.close(mode: closeMode))) {
      _exiting = false;
      return;
    }
    try {
      await _device.setAwake(false);
      if (!mounted) return;
      setState(() => _allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    } catch (_) {
      if (!mounted) return;
      _kitchen.open(foreground: false);
      setState(() {
        _exiting = false;
        _ready = false;
        _error = '画面点灯の解除を確認できません。もう一度「終了」を押してください。';
      });
    }
  }

  Future<void> _addTimer() async {
    final value = await showDialog<(String, Duration)>(
      context: context,
      builder: (_) => const _TimerEditor(),
    );
    if (value != null && mounted && !_exiting && _ready) {
      String? createdId;
      final saved = await _perform((k) {
        createdId = k.create(name: value.$1, duration: value.$2);
      });
      if (saved && mounted) setState(() => _selectedTimerId = createdId);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _back();
    },
    child: Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        automaticallyImplyLeading: false,
        title: const Text('キッチン'),
        actions: [TextButton(onPressed: _exit, child: const Text('終了'))],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_rebootSnapshot != null)
              MaterialBanner(
                content: const Text('端末再起動のためタイマーを確認してください。'),
                actions: [
                  TextButton(
                    onPressed: _saving ? null : _reviewReboot,
                    child: const Text('確認する'),
                  ),
                ],
              ),
            if (_notificationTargetId != null)
              MaterialBanner(
                content: Text(_notificationTargetMessage),
                actions: [
                  TextButton(
                    onPressed: () {
                      widget.notificationTarget?.value = null;
                      setState(() => _notificationTargetId = null);
                    },
                    child: const Text('閉じる'),
                  ),
                ],
              ),
            if (_notificationWarning != null && _kitchen.hasActiveTimers)
              MaterialBanner(
                content: Text('${_notificationWarning!} 画面内タイマーは引き続き利用できます。'),
                actions: [
                  TextButton(
                    onPressed: _saving ? null : _configureNotifications,
                    child: const Text('設定'),
                  ),
                ],
              ),
            if (_error != null)
              MaterialBanner(
                content: Text(_error!),
                actions: [
                  TextButton(
                    onPressed: () => _applyLifecycle(
                      WidgetsBinding.instance.lifecycleState ??
                          AppLifecycleState.resumed,
                    ),
                    child: const Text('再試行'),
                  ),
                ],
              ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 720;
                  final scale = MediaQuery.textScalerOf(context).scale(18) / 18;
                  final compact =
                      !wide && (constraints.maxHeight < 520 || scale > 1.3);
                  final timers = AnimatedBuilder(
                    animation: _kitchen,
                    builder: (context, _) => _timerPanel(compact: compact),
                  );
                  final recipes = KitchenScope(
                    controller: _kitchen,
                    perform: _perform,
                    child: Navigator(
                      key: _navigator,
                      onGenerateRoute: (_) => MaterialPageRoute<void>(
                        builder: (context) => _KitchenStart(
                          onOpenRecipes: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  HomeScreen(controller: widget.library),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                  if (wide) {
                    return Row(
                      children: [
                        SizedBox(
                          width: constraints.maxWidth * .34,
                          child: SingleChildScrollView(child: timers),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(child: recipes),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: constraints.maxHeight * .62,
                        ),
                        child: SingleChildScrollView(child: timers),
                      ),
                      const Divider(height: 1),
                      Expanded(child: recipes),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _timerPanel({required bool compact}) {
    final time = DateTime.now();
    final clock =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    final selected = _selectedTimer;
    final remaining =
        selected?.remainingAt(now: _device.now()) ?? Duration.zero;
    final seconds = (remaining.inMilliseconds / 1000).ceil();
    final display =
        '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
    final enabled = _ready && !_exiting && !_saving;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'キッチンタイマー',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
              ),
              Text('現在 $clock', style: TextStyle(color: _accent)),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            key: const Key('main_kitchen_timer'),
            padding: EdgeInsets.all(compact ? 12 : 20),
            decoration: BoxDecoration(
              color: RecipeTheme.sage,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: RecipeTheme.outline),
            ),
            child: Column(
              children: [
                Text(
                  selected?.name ?? 'タイマー',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Semantics(
                  label: selected == null
                      ? 'タイマー未設定'
                      : '${selected.name}、${_status(selected)}',
                  excludeSemantics: true,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      display,
                      key: const Key('main_timer_digits'),
                      style: TextStyle(
                        fontSize: compact ? 70 : 96,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -3,
                        color: RecipeTheme.ink,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
                Text(selected == null ? '時間を設定してください' : _status(selected)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (final (key, label, duration) in [
                      ('timer_preset_10m', '10分', const Duration(minutes: 10)),
                      ('timer_preset_1m', '1分', const Duration(minutes: 1)),
                      ('timer_preset_10s', '10秒', const Duration(seconds: 10)),
                    ])
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: OutlinedButton(
                            key: Key(key),
                            onPressed: enabled
                                ? () => _addPreset(duration)
                                : null,
                            child: Text(label),
                          ),
                        ),
                      ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: const Key('reset_main_timer'),
                        onPressed: enabled && selected != null
                            ? () => _resetSelectedTimer(selected)
                            : null,
                        child: const Text('リセット'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        key: const Key('toggle_main_timer'),
                        onPressed: enabled && selected != null
                            ? () => _mainTimerAction(selected)
                            : null,
                        child: Text(switch (selected?.state) {
                          KitchenTimerState.running => '一時停止',
                          KitchenTimerState.paused => '再開',
                          KitchenTimerState.finished =>
                            selected!.isFinishedAcknowledged ? '再設定' : '終了を確認',
                          KitchenTimerState.ready => '開始',
                          KitchenTimerState.cancelled => '再設定',
                          null => '開始',
                        }),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(child: Text('ほかのタイマー')),
              TextButton.icon(
                onPressed: enabled ? _addTimer : null,
                icon: const Icon(Icons.add),
                label: const Text('追加'),
              ),
            ],
          ),
          for (final timer
              in _displayTimers
                  .where((timer) => timer.id != selected?.id)
                  .take(compact ? 1 : 2))
            ListTile(
              dense: true,
              title: Text(timer.name),
              trailing: Text(_status(timer)),
              onTap: () => setState(() => _selectedTimerId = timer.id),
            ),
          if (_kitchen.timers.isNotEmpty)
            TextButton(
              onPressed: _showTimers,
              child: Text('すべてのタイマー（${_kitchen.timers.length}件）'),
            ),
        ],
      ),
    );
  }

  KitchenTimer? get _selectedTimer {
    if (_selectedTimerId == '') return null;
    for (final timer in _kitchen.timers) {
      if (timer.id == _selectedTimerId) return timer;
    }
    return _displayTimers.isEmpty ? null : _displayTimers.first;
  }

  Future<void> _resetSelectedTimer(KitchenTimer timer) async {
    if (timer.state == KitchenTimerState.ready) {
      final saved = await _perform((k) => k.remove(timer.id));
      if (saved && mounted) setState(() => _selectedTimerId = '');
      return;
    }
    await _perform((k) => k.reset(timer.id));
  }

  Future<void> _addPreset(Duration duration) async {
    final selected = _selectedTimer;
    if (selected == null ||
        selected.state == KitchenTimerState.finished ||
        selected.state == KitchenTimerState.cancelled) {
      String? createdId;
      final saved = await _perform((k) {
        createdId = k.createReady(name: 'タイマー', duration: duration);
      });
      if (saved && mounted) setState(() => _selectedTimerId = createdId);
      return;
    }
    await _perform((k) {
      if (selected.state == KitchenTimerState.ready) {
        k.addConfiguredDuration(selected.id, duration);
      } else {
        k.extend(selected.id, duration);
      }
    });
  }

  Future<void> _mainTimerAction(KitchenTimer timer) => _perform((k) {
    switch (timer.state) {
      case KitchenTimerState.ready:
        k.start(timer.id);
      case KitchenTimerState.running:
        k.pause(timer.id);
      case KitchenTimerState.paused:
        k.resume(timer.id);
      case KitchenTimerState.finished:
        if (timer.isFinishedAcknowledged) {
          k.reset(timer.id);
        } else {
          k.acknowledge(timer.id);
        }
      case KitchenTimerState.cancelled:
        k.reset(timer.id);
    }
  }).then((_) {});

  Future<void> _showTimers() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: FractionallySizedBox(
        heightFactor: .8,
        child: AnimatedBuilder(
          animation: _kitchen,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('タイマー', style: TextStyle(fontSize: 24)),
              for (final timer in _displayTimers) _timerRow(timer),
              FilledButton(
                onPressed: _ready && !_saving ? _addTimer : null,
                child: const Text('タイマーを追加'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  List<KitchenTimer> get _displayTimers => [..._kitchen.timers]
    ..sort((a, b) {
      if (a.id == _notificationTargetId && b.id != _notificationTargetId) {
        return -1;
      }
      if (b.id == _notificationTargetId && a.id != _notificationTargetId) {
        return 1;
      }
      int rank(KitchenTimer timer) =>
          timer.state == KitchenTimerState.finished &&
              !timer.isFinishedAcknowledged
          ? 0
          : timer.state == KitchenTimerState.running
          ? 1
          : 2;
      final category = rank(a).compareTo(rank(b));
      if (category != 0) return category;
      if (a.deadline != null && b.deadline != null) {
        final deadlineOrder = a.deadline!.compareTo(b.deadline!);
        if (deadlineOrder != 0) return deadlineOrder;
      }
      final createdOrder = a.createdAt.compareTo(b.createdAt);
      return createdOrder != 0 ? createdOrder : a.id.compareTo(b.id);
    });

  String get _notificationTargetMessage {
    KitchenTimer? target;
    for (final timer in _kitchen.timers) {
      if (timer.id == _notificationTargetId) {
        target = timer;
        break;
      }
    }
    return target == null
        ? '通知からキッチンを開きました。対象タイマーは現在の保存状態にありません。'
        : '通知から「${target.name}」を開きました。工程は自動で進めていません。';
  }

  String _status(KitchenTimer timer) {
    final remaining = timer.remainingAt(now: _device.now());
    final seconds = (remaining.inMilliseconds / 1000).ceil();
    final duration =
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    return switch (timer.state) {
      KitchenTimerState.ready => '設定 $duration',
      KitchenTimerState.running => '残り $duration',
      KitchenTimerState.paused => '一時停止 $duration',
      KitchenTimerState.finished =>
        timer.isFinishedAcknowledged ? '終了・確認済み' : '終了',
      KitchenTimerState.cancelled => '停止済み',
    };
  }

  Widget _timerRow(KitchenTimer timer) => RecipeSection(
    children: [
      Text(
        timer.name,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      ),
      Text(
        _status(timer),
        style: TextStyle(
          fontSize: 26,
          color: timer.state == KitchenTimerState.finished
              ? RecipeTheme.warning
              : null,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      Wrap(
        spacing: 8,
        children: [
          if (timer.state == KitchenTimerState.running)
            _action('一時停止', (k) => k.pause(timer.id)),
          if (timer.state == KitchenTimerState.paused)
            _action('再開', (k) => k.resume(timer.id)),
          if (timer.state == KitchenTimerState.ready)
            _action('開始', (k) => k.start(timer.id)),
          if (timer.state == KitchenTimerState.running ||
              timer.state == KitchenTimerState.paused) ...[
            _action(
              '+1分',
              (k) => k.extend(timer.id, const Duration(minutes: 1)),
            ),
            _action('停止', (k) => k.cancel(timer.id)),
          ],
          if (timer.state == KitchenTimerState.finished &&
              !timer.isFinishedAcknowledged)
            _action('終了を確認', (k) => k.acknowledge(timer.id)),
          if (timer.state != KitchenTimerState.ready)
            _action('リセット', (k) => k.reset(timer.id)),
          if (timer.state == KitchenTimerState.ready ||
              timer.state == KitchenTimerState.cancelled ||
              (timer.state == KitchenTimerState.finished &&
                  timer.isFinishedAcknowledged))
            _action('閉じる', (k) => k.remove(timer.id)),
        ],
      ),
    ],
  );

  Widget _action(String label, void Function(KitchenController) action) =>
      OutlinedButton(
        onPressed: _ready && !_exiting && !_saving
            ? () => _perform(action)
            : null,
        child: Text(label),
      );
}

class _KitchenStart extends StatelessWidget {
  const _KitchenStart({required this.onOpenRecipes});
  final VoidCallback onOpenRecipes;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      RecipeSection(
        children: [
          const Text('時計とタイマーを、調理のおともに。', style: TextStyle(fontSize: 22)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onOpenRecipes,
            icon: const Icon(Icons.menu_book_outlined),
            label: const Text('レシピを開く'),
          ),
        ],
      ),
      const SizedBox(height: 16),
      const Text(
        'キッチンを開いている間は画面を点灯します。\nタイマーは端末に保存します。'
        '通知を許可すると、画面を閉じた後も終了を知らせます。端末のサイレント設定、音量0、電池制限、強制停止中は音や定刻配送を保証できません。',
      ),
    ],
  );
}

class _TimerEditor extends StatefulWidget {
  const _TimerEditor();
  @override
  State<_TimerEditor> createState() => _TimerEditorState();
}

class _TimerEditorState extends State<_TimerEditor> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(text: 'タイマー');
  final _minutes = TextEditingController(text: '5');
  final _seconds = TextEditingController(text: '0');
  @override
  void dispose() {
    _name.dispose();
    _minutes.dispose();
    _seconds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('タイマーを追加'),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextFormField(
                controller: _name,
                maxLength: 60,
                decoration: const InputDecoration(labelText: '名前'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? '名前を入力してください'
                    : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextFormField(
                controller: _minutes,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '分'),
                validator: (value) {
                  final minutes = int.tryParse(value ?? '');
                  return minutes == null || minutes < 0 || minutes > 1439
                      ? '0〜1439分で入力してください'
                      : null;
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextFormField(
                controller: _seconds,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '秒'),
                validator: (value) {
                  final seconds = int.tryParse(value ?? '');
                  if (seconds == null || seconds < 0 || seconds > 59) {
                    return '0〜59秒で入力してください';
                  }
                  if ((int.tryParse(_minutes.text) ?? 0) == 0 && seconds == 0) {
                    return '1秒以上にしてください';
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('戻る'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, (
              _name.text.trim(),
              Duration(
                minutes: int.parse(_minutes.text),
                seconds: int.parse(_seconds.text),
              ),
            ));
          }
        },
        child: const Text('開始'),
      ),
    ],
  );
}
