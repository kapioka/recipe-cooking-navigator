import 'dart:async';

import 'package:flutter/material.dart';

import '../data/cooking_store.dart';
import '../domain/recipe_document.dart';
import '../platform/cooking_device.dart';

enum _CookingMenuAction { complete, help }

class CookingScreen extends StatefulWidget {
  const CookingScreen({
    required this.recipe,
    required this.store,
    required this.initialIndex,
    super.key,
  });
  final RecipeDocument recipe;
  final CookingStore store;
  final int initialIndex;
  @override
  State<CookingScreen> createState() => _CookingScreenState();
}

class _CookingScreenState extends State<CookingScreen> {
  late int index = widget.initialIndex;
  late final device = CookingDevice();
  final scroll = ScrollController();
  final speaking = ValueNotifier<bool>(false);
  final timerVersion = ValueNotifier<int>(0);
  bool busy = false;
  bool voiceOn = false;
  String voiceState = '音声OFF';
  String? error;
  DateTime? deadline;
  String? timerStep;
  int timerExtraSeconds = 0;
  int timerAdjustmentSeconds = 0;
  int? timerOriginalSeconds;
  bool timerFinished = false;
  Timer? ticker;
  double dragDistance = 0;
  bool panelOpen = false;
  bool allowPop = false;
  static const _background = Color(0xFFFFFAF6);
  static const _rust = Color(0xFFB6401F);
  static const _rustDark = Color(0xFF96361F);
  static const _softRust = Color(0xFFF8E9DF);
  static const _border = Color(0xFFE8CFC0);
  List<Map<String, dynamic>> get steps => widget.recipe.steps;
  Map<String, dynamic> get step => steps[index];

  @override
  void initState() {
    super.initState();
    device.onEvent = _event;
    _invoke('wake');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _showInitialHelp();
      }
    });
  }

  Future<void> _showInitialHelp() async {
    try {
      final data = await widget.store.read();
      if (data['help_seen'] == true || !mounted) {
        return;
      }
      await widget.store.markHelpSeen();
      if (mounted) {
        _help();
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = '画面操作の説明の表示状態を保存できませんでした。');
      }
    }
  }

  @override
  void dispose() {
    ticker?.cancel();
    scroll.dispose();
    speaking.dispose();
    timerVersion.dispose();
    device.close().catchError((Object _) {});
    super.dispose();
  }

  Future<void> _invoke(String method, [dynamic arg]) async {
    try {
      await device.invoke(method, arg);
    } catch (_) {
      if (method == 'speak') speaking.value = false;
      if (mounted) {
        setState(() {
          error = '端末機能を利用できません。画面ボタンで操作できます。';
          voiceOn = false;
        });
      }
    }
  }

  void _event(String method, dynamic value) {
    if (!mounted) return;
    if (method == 'voiceState') {
      setState(() {
        voiceState = value as String;
        if (voiceState == '音声OFF') {
          voiceOn = false;
        }
      });
    } else if (method == 'voiceError') {
      setState(() {
        error = value as String;
        voiceOn = false;
        voiceState = '音声OFF';
      });
    } else if (method == 'speakingState') {
      speaking.value = value == true;
    } else if (method == 'recognized') {
      final command = (value as String).replaceAll(RegExp(r'[\s。、！!？?]'), '');
      if (panelOpen &&
          command != '調理画面' &&
          command != '音声停止' &&
          command != '読み上げ停止') {
        return;
      }
      switch (command) {
        case '次':
        case '次へ':
          _move(index + 1);
        case '戻る':
        case '前へ':
          _move(index - 1);
        case '材料':
          _materials();
        case '全体工程':
          _stepList();
        case '調理画面':
          if (panelOpen) Navigator.of(context).pop();
        case 'タイマー開始':
          _startTimer();
        case 'タイマー停止':
          _stopTimer();
        case '残り時間':
          _invoke('speak', '残り${_remaining()}秒です。');
        case '読んで':
        case 'もう一度':
          _startSpeaking();
        case '音声停止':
        case '読み上げ停止':
          _stopSpeaking();
        default:
          setState(() => error = '操作できる言葉ではありません。次へ・前へ・材料・読んで、などで操作できます。');
      }
    }
  }

  Future<void> _move(int target) async {
    if (busy || target < 0 || target >= steps.length || target == index) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    await _stopSpeaking();
    try {
      await widget.store.savePosition(
        widget.recipe.id,
        widget.recipe.revision,
        steps[target]['id'] as String,
      );
      if (mounted) {
        setState(() {
          index = target;
          if (deadline == null) timerExtraSeconds = 0;
        });
        timerVersion.value++;
        if (scroll.hasClients) scroll.jumpTo(0);
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = '調理位置を保存できませんでした。工程を移動していません。もう一度操作してください。');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  int _remaining() {
    if (deadline == null) return 0;
    final milliseconds = deadline!.difference(DateTime.now()).inMilliseconds;
    if (milliseconds <= 0) return 0;
    return ((milliseconds + 999) ~/ 1000).clamp(0, 999999);
  }

  void _startTimer() {
    if (deadline != null && !timerFinished) {
      setState(() => error = '実行中のタイマーを停止してから開始してください。');
      return;
    }
    final recipeSeconds = step['timer_seconds'] as int? ?? 0;
    final seconds = recipeSeconds + timerExtraSeconds;
    if (seconds <= 0) {
      setState(() => error = '時間を追加してからタイマーを開始してください。');
      return;
    }
    ticker?.cancel();
    setState(() {
      deadline = DateTime.now().add(Duration(seconds: seconds));
      timerStep = step['title'] as String;
      timerAdjustmentSeconds = timerExtraSeconds;
      timerOriginalSeconds = recipeSeconds;
      timerFinished = false;
      error = null;
    });
    timerExtraSeconds = 0;
    timerVersion.value++;
    _runTimerTicker();
  }

  void _runTimerTicker() {
    ticker?.cancel();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_remaining() == 0) timerFinished = true;
      });
      timerVersion.value++;
      if (timerFinished) {
        ticker?.cancel();
        _invoke('speak', 'タイマーが終了しました。仕上がりを確認してください。');
      }
    });
  }

  void _addTimerSeconds(int seconds) {
    setState(() {
      error = null;
      if (deadline == null) {
        timerExtraSeconds += seconds;
      } else if (timerFinished) {
        deadline = DateTime.now().add(Duration(seconds: seconds));
        timerAdjustmentSeconds = seconds;
        timerFinished = false;
        _runTimerTicker();
      } else {
        deadline = deadline!.add(Duration(seconds: seconds));
        timerAdjustmentSeconds += seconds;
      }
    });
    timerVersion.value++;
  }

  void _resetTimerAdjustments() {
    if (deadline == null) {
      if (timerExtraSeconds == 0) return;
      setState(() {
        timerExtraSeconds = 0;
        error = null;
      });
    } else {
      if (timerFinished || timerAdjustmentSeconds == 0) return;
      setState(() {
        deadline = deadline!.subtract(
          Duration(seconds: timerAdjustmentSeconds),
        );
        timerAdjustmentSeconds = 0;
        timerFinished = _remaining() == 0;
        error = null;
      });
      if (timerFinished) {
        ticker?.cancel();
        _invoke('speak', 'タイマーが終了しました。仕上がりを確認してください。');
      }
    }
    timerVersion.value++;
  }

  void _stopTimer() {
    ticker?.cancel();
    setState(() {
      deadline = null;
      timerFinished = false;
      timerStep = null;
      timerExtraSeconds = 0;
      timerAdjustmentSeconds = 0;
      timerOriginalSeconds = null;
    });
    timerVersion.value++;
  }

  String _speechText() => [
    step['title'],
    step['instruction'],
    ...widget.recipe.ingredientsFor(step),
    if (step['heat'] != null) '火加減 ${step['heat']}',
    if (step['timer_seconds'] != null) '時間の目安 ${step['timer_seconds']}秒',
    '完了判断 ${step['done_when']}',
  ].join('。');

  void _startSpeaking() {
    speaking.value = true;
    _invoke('speak', _speechText());
  }

  Future<void> _stopSpeaking() async {
    speaking.value = false;
    await _invoke('stopSpeaking');
  }

  void _toggleSpeaking() {
    if (speaking.value) {
      _stopSpeaking();
    } else {
      _startSpeaking();
    }
  }

  Future<void> _moveAndSpeak(int target) async {
    if (target != index) await _move(target);
    if (mounted && index == target) _startSpeaking();
  }

  Future<void> _panel({required String title, required Widget child}) async {
    if (panelOpen) {
      return;
    }
    panelOpen = true;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag: true,
      showDragHandle: true,
      backgroundColor: _background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * .82,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 56),
                      textStyle: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close, size: 26),
                    label: const Text('調理画面へ戻る'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: child),
          ],
        ),
      ),
    );
    panelOpen = false;
  }

  void _materials() => _panel(
    title: '材料一覧',
    child: ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      itemCount: widget.recipe.ingredients.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, position) {
        final ingredient = widget.recipe.ingredients[position];
        return ListTile(
          minVerticalPadding: 16,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          title: Text(
            ingredient.name,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${ingredient.quantity}${ingredient.note == null ? '' : ' ${ingredient.note}'}',
              style: const TextStyle(fontSize: 19, height: 1.35),
            ),
          ),
        );
      },
    ),
  );

  void _stepList() => _panel(
    title: '工程一覧',
    child: ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: steps.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (sheetContext, position) => ListTile(
        minVerticalPadding: 16,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        tileColor: position == index ? _softRust : Colors.transparent,
        selected: position == index,
        leading: CircleAvatar(
          backgroundColor: position == index ? _rust : _softRust,
          foregroundColor: position == index ? Colors.white : _rustDark,
          child: Text(
            '${position + 1}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(
          steps[position]['title'] as String,
          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
        ),
        subtitle: position == index
            ? const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('現在位置', style: TextStyle(fontSize: 17)),
              )
            : null,
        onTap: () {
          Navigator.pop(sheetContext);
          _move(position);
        },
      ),
    ),
  );

  void _help() => _panel(
    title: '画面操作の説明',
    child: const SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: Text(
        '左30%をタップ：前の工程\n中央40%をタップ：音声操作パネルを開く\n右30%をタップ：次の工程\n\n左へスワイプ：次へ\n右へスワイプ：前へ\n上下スクロール：長い本文を読む\n\n画面上部の「音声操作」ボタン：音声操作のON・OFFと使える言葉を確認\n\n「読み上げ」は短く押すと開始・停止、長押しすると読み上げの詳細を開きます。\n\n工程移動は作業の完了判定ではありません。\n途中位置は自動保存されます。タイマーは再起動すると停止します。\n\n音声操作は端末の認識機能を使います。端末設定により音声が認識サービスへ送信される場合があります。',
        style: TextStyle(fontSize: 20, height: 1.55),
      ),
    ),
  );

  void _toggleVoice() {
    setState(() => voiceOn = !voiceOn);
    _invoke('voice', voiceOn);
  }

  String _timerButtonLabel() {
    if (deadline != null) {
      return timerFinished ? 'タイマー終了' : '残り${_remaining()}秒';
    }
    final seconds = (step['timer_seconds'] as int? ?? 0) + timerExtraSeconds;
    if (seconds == 0) return 'タイマー設定';
    return '$seconds秒タイマー';
  }

  void _operations() => _panel(
    title: '音声操作',
    child: ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _softRust,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            voiceState,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(68),
            textStyle: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          onPressed: _toggleVoice,
          icon: Icon(
            voiceOn ? Icons.mic_off_outlined : Icons.mic_outlined,
            size: 30,
          ),
          label: Text(voiceOn ? '音声操作をOFFにする' : '音声操作をONにする'),
        ),
        const SizedBox(height: 20),
        Container(
          key: const Key('voice_command_list'),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _background,
            border: Border.all(color: _border, width: 1.5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.record_voice_over_outlined, color: _rustDark),
                  SizedBox(width: 10),
                  Text(
                    '使える言葉',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              SizedBox(height: 16),
              Text(
                '工程移動：次・次へ／戻る・前へ\n'
                '表示：材料／全体工程／調理画面\n'
                'タイマー：タイマー開始／タイマー停止／残り時間\n'
                '読み上げ：読んで／もう一度／音声停止／読み上げ停止',
                style: TextStyle(fontSize: 19, height: 1.65),
              ),
              SizedBox(height: 12),
              Text(
                '※読み上げを声で停めるには、音声操作をONにしてください。',
                style: TextStyle(fontSize: 17, height: 1.45),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          key: const Key('screen_controls_help_button'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(64),
            textStyle: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
          ),
          onPressed: () {
            Navigator.pop(context);
            WidgetsBinding.instance.addPostFrameCallback((_) => _help());
          },
          icon: const Icon(Icons.touch_app_outlined, size: 28),
          label: const Text('画面操作の説明を見る'),
        ),
      ],
    ),
  );

  void _readingDetails() => _panel(
    title: '読み上げの詳細',
    child: ValueListenableBuilder<bool>(
      valueListenable: speaking,
      builder: (context, isSpeaking, _) => ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _softRust,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              isSpeaking ? '現在の工程を読み上げています' : '読み上げは停止しています',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const Key('reading_toggle_detail'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(68),
              textStyle: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            onPressed: _toggleSpeaking,
            icon: Icon(
              isSpeaking
                  ? Icons.stop_circle_outlined
                  : Icons.volume_up_outlined,
              size: 30,
            ),
            label: Text(isSpeaking ? '読み上げを停止' : '読み上げを開始'),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            key: const Key('restart_reading_button'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(64),
              textStyle: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
            onPressed: _startSpeaking,
            icon: const Icon(Icons.replay, size: 28),
            label: const Text('現在の工程をはじめから'),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            key: const Key('read_previous_step_button'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(64),
              textStyle: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
            onPressed: index == 0
                ? null
                : () {
                    final target = index - 1;
                    Navigator.pop(context);
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _moveAndSpeak(target),
                    );
                  },
            icon: const Icon(Icons.skip_previous, size: 30),
            label: const Text('前の工程へ移動して読み上げ'),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            key: const Key('read_next_step_button'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(64),
              textStyle: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
            onPressed: index == steps.length - 1
                ? null
                : () {
                    final target = index + 1;
                    Navigator.pop(context);
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _moveAndSpeak(target),
                    );
                  },
            icon: const Icon(Icons.skip_next, size: 30),
            label: const Text('次の工程へ移動して読み上げ'),
          ),
        ],
      ),
    ),
  );

  void _timerDetails() => _panel(
    title: 'タイマー',
    child: ValueListenableBuilder<int>(
      valueListenable: timerVersion,
      builder: (context, _, _) {
        final recipeSeconds = deadline == null
            ? step['timer_seconds'] as int? ?? 0
            : timerOriginalSeconds ?? 0;
        final displaySeconds = deadline == null
            ? recipeSeconds + timerExtraSeconds
            : _remaining();
        final canResetAdjustments = deadline == null
            ? timerExtraSeconds > 0
            : !timerFinished && timerAdjustmentSeconds > 0;
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          children: [
            Text(
              'レシピの設定：$recipeSeconds秒',
              key: const Key('recipe_timer_seconds'),
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              decoration: BoxDecoration(
                color: _softRust,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Text(
                    deadline == null
                        ? '設定時間'
                        : timerFinished
                        ? 'タイマー終了'
                        : '残り時間',
                    style: const TextStyle(fontSize: 20),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$displaySeconds秒',
                    key: const Key('timer_detail_seconds'),
                    style: const TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: _timerAddButton('+10分', 600, 'add_10_minutes')),
                const SizedBox(width: 8),
                Expanded(child: _timerAddButton('+1分', 60, 'add_1_minute')),
                const SizedBox(width: 8),
                Expanded(child: _timerAddButton('+10秒', 10, 'add_10_seconds')),
              ],
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              key: const Key('reset_timer_adjustments'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(62),
                textStyle: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onPressed: canResetAdjustments ? _resetTimerAdjustments : null,
              icon: const Icon(Icons.restart_alt, size: 28),
              label: const Text('追加した時間をリセット'),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('timer_toggle_detail'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(70),
                backgroundColor: deadline == null ? _rust : _rustDark,
                textStyle: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onPressed: deadline == null && displaySeconds == 0
                  ? null
                  : deadline == null
                  ? _startTimer
                  : _stopTimer,
              icon: Icon(
                deadline == null ? Icons.play_arrow : Icons.stop,
                size: 32,
              ),
              label: Text(deadline == null ? 'タイマー開始' : 'タイマー停止'),
            ),
          ],
        );
      },
    ),
  );

  Widget _timerAddButton(String label, int seconds, String keyName) =>
      OutlinedButton(
        key: Key(keyName),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 66),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          textStyle: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
        ),
        onPressed: () => _addTimerSeconds(seconds),
        child: Text(label),
      );

  Widget _infoCard({required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _background,
      border: Border.all(color: _border),
      borderRadius: BorderRadius.circular(12),
    ),
    child: child,
  );

  Widget _detailRow(IconData icon, String text, {bool divider = false}) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: divider
            ? const BoxDecoration(
                border: Border(bottom: BorderSide(color: _border)),
              )
            : null,
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: _softRust,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: _rust),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _controlButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    VoidCallback? onLongPress,
    bool filled = false,
    bool soft = false,
    Key? key,
  }) {
    final style = filled || soft
        ? FilledButton.styleFrom(
            backgroundColor: soft ? _softRust : _rust,
            foregroundColor: soft ? const Color(0xFF211813) : Colors.white,
            disabledBackgroundColor: _softRust,
            disabledForegroundColor: _rust.withValues(alpha: .45),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          )
        : OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF211813),
            side: const BorderSide(color: _rust),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          );
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 24),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
    return filled || soft
        ? FilledButton(
            key: key,
            onPressed: onPressed,
            onLongPress: onLongPress,
            style: style,
            child: child,
          )
        : OutlinedButton(
            key: key,
            onPressed: onPressed,
            onLongPress: onLongPress,
            style: style,
            child: child,
          );
  }

  Future<void> _exit(bool complete) async {
    if (busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(complete ? '調理を完了しますか？' : '調理を中断しますか？'),
        content: Text(
          complete
              ? '調理した記録を保存します。タイマーと読み上げを停止します。'
              : '途中位置は保存済みです。タイマーと音声を停止します。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(complete ? '完了する' : '中断する'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => busy = true);
    try {
      if (complete) {
        await widget.store.complete(widget.recipe.id, widget.recipe.revision);
      }
      await _invoke('close');
      if (mounted) {
        setState(() => allowPop = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.of(context).pop();
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          error = '完了記録を保存できませんでした。再試行してください。';
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final timerSeconds = step['timer_seconds'] as int?;
    final heat = step['heat'] as String?;
    return PopScope(
      canPop: allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exit(false);
      },
      child: Theme(
        data: Theme.of(context).copyWith(
          scaffoldBackgroundColor: _background,
          appBarTheme: const AppBarTheme(
            backgroundColor: _background,
            foregroundColor: Color(0xFF211813),
            surfaceTintColor: Colors.transparent,
          ),
          bottomSheetTheme: const BottomSheetThemeData(
            showDragHandle: true,
            dragHandleColor: _rustDark,
            dragHandleSize: Size(64, 7),
          ),
        ),
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: '調理を中断',
              onPressed: () => _exit(false),
              icon: const Icon(Icons.arrow_back),
            ),
            title: Text(
              widget.recipe.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            actions: [
              PopupMenuButton<_CookingMenuAction>(
                tooltip: 'その他の操作',
                onSelected: (action) {
                  switch (action) {
                    case _CookingMenuAction.complete:
                      _exit(true);
                    case _CookingMenuAction.help:
                      _help();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _CookingMenuAction.complete,
                    height: 72,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.check_circle_outline, size: 30),
                      title: Text(
                        '調理を完了',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  PopupMenuItem(
                    value: _CookingMenuAction.help,
                    height: 72,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.help_outline, size: 30),
                      title: Text(
                        '画面操作の説明',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            bottom: false,
            child: Column(
              children: [
                if (busy) const LinearProgressIndicator(),
                if (error != null)
                  Semantics(
                    liveRegion: true,
                    child: Container(
                      width: double.infinity,
                      color: Theme.of(context).colorScheme.errorContainer
                          .withValues(alpha: .55),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, bounds) => GestureDetector(
                      key: const Key('cooking_gesture'),
                      behavior: HitTestBehavior.opaque,
                      excludeFromSemantics: true,
                      onTapUp: (event) {
                        final fraction =
                            event.localPosition.dx / bounds.maxWidth;
                        if (fraction < .3) {
                          _move(index - 1);
                        } else if (fraction >= .7) {
                          _move(index + 1);
                        } else {
                          _operations();
                        }
                      },
                      onHorizontalDragStart: (_) => dragDistance = 0,
                      onHorizontalDragUpdate: (event) {
                        dragDistance += event.delta.dx;
                      },
                      onHorizontalDragEnd: (_) {
                        if (dragDistance.abs() >= 60) {
                          _move(index + (dragDistance < 0 ? 1 : -1));
                        }
                      },
                      child: SingleChildScrollView(
                        controller: scroll,
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
                        child: SizedBox(
                          width: double.infinity,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '工程 ${index + 1} / ${steps.length}',
                                      style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Semantics(
                                    liveRegion: true,
                                    label: '音声操作状態、$voiceState',
                                    button: true,
                                    child: OutlinedButton.icon(
                                      key: const Key('voice_state'),
                                      style: OutlinedButton.styleFrom(
                                        minimumSize: const Size(0, 56),
                                        backgroundColor: _softRust,
                                        foregroundColor: _rustDark,
                                        side: const BorderSide(color: _rust),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 10,
                                        ),
                                        textStyle: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      onPressed: _operations,
                                      icon: Icon(
                                        voiceOn
                                            ? Icons.mic_outlined
                                            : Icons.mic_off_outlined,
                                        size: 24,
                                      ),
                                      label: Text(
                                        '音声操作 ${voiceOn ? 'ON' : 'OFF'}',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (deadline != null) ...[
                                const SizedBox(height: 10),
                                Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    '$timerStep：${timerFinished ? 'タイマー終了・仕上がりを確認' : '残り ${_remaining()}秒'}',
                                    key: const Key('timer_status'),
                                    style: TextStyle(
                                      color: timerFinished
                                          ? Theme.of(context).colorScheme.error
                                          : _rustDark,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 28),
                              Text(
                                step['title'] as String,
                                key: const Key('cooking_step_title'),
                                style: const TextStyle(
                                  fontSize: 32,
                                  height: 1.25,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF211813),
                                ),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                step['instruction'] as String,
                                style: const TextStyle(
                                  fontSize: 22,
                                  height: 1.55,
                                  color: Color(0xFF211813),
                                ),
                              ),
                              const SizedBox(height: 20),
                              _infoCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'この工程の材料・分量',
                                      style: TextStyle(
                                        color: _rustDark,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    for (final text
                                        in widget.recipe.ingredientsFor(step))
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 3,
                                        ),
                                        child: Text(
                                          '・ $text',
                                          style: const TextStyle(
                                            fontSize: 17,
                                            height: 1.3,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              if (heat != null || timerSeconds != null) ...[
                                const SizedBox(height: 10),
                                if (heat != null)
                                  _detailRow(
                                    Icons.local_fire_department_outlined,
                                    heat,
                                    divider: timerSeconds != null,
                                  ),
                                if (timerSeconds != null)
                                  _detailRow(
                                    Icons.schedule_outlined,
                                    '$timerSeconds秒',
                                  ),
                              ],
                              const SizedBox(height: 10),
                              _infoCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '完了判断',
                                      style: TextStyle(
                                        color: _rustDark,
                                        fontSize: 19,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      step['done_when'] as String,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        height: 1.45,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),
                              for (final id in step['utensil_ids'] as List)
                                Text(
                                  '器具：${(widget.recipe.recipeData['utensils'] as List).firstWhere((u) => u['id'] == id)['name']}',
                                  style: const TextStyle(fontSize: 16),
                                ),
                              for (final task in step['parallel_tasks'] as List)
                                Text(
                                  '並行作業：$task',
                                  style: const TextStyle(fontSize: 16),
                                ),
                              if (step['next_preview'] != null)
                                Text(
                                  '次の工程：${step['next_preview']}',
                                  style: const TextStyle(fontSize: 16),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: _background,
                border: Border(top: BorderSide(color: _border)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 12,
                    offset: Offset(0, -3),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _controlButton(
                            key: const Key('materials_button'),
                            label: '材料を見る',
                            icon: Icons.shopping_bag_outlined,
                            onPressed: _materials,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _controlButton(
                            key: const Key('steps_button'),
                            label: '工程一覧',
                            icon: Icons.format_list_bulleted,
                            onPressed: _stepList,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ValueListenableBuilder<bool>(
                            valueListenable: speaking,
                            builder: (context, isSpeaking, _) => Semantics(
                              hint: '長押しで読み上げの詳細を開きます',
                              child: _controlButton(
                                key: const Key('speak_button'),
                                label: isSpeaking ? '読み上げ停止' : '読み上げ',
                                icon: isSpeaking
                                    ? Icons.stop_circle_outlined
                                    : Icons.volume_up_outlined,
                                onPressed: _toggleSpeaking,
                                onLongPress: _readingDetails,
                                filled: true,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _controlButton(
                            key: const Key('timer_button'),
                            label: _timerButtonLabel(),
                            icon: Icons.timer_outlined,
                            onPressed: _timerDetails,
                            filled: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _controlButton(
                            key: const Key('previous_step_button'),
                            label: '前へ',
                            icon: Icons.arrow_back,
                            onPressed: busy || index == 0
                                ? null
                                : () => _move(index - 1),
                            filled: true,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _controlButton(
                            key: const Key('screen_controls_button'),
                            label: '操作方法',
                            icon: Icons.touch_app_outlined,
                            onPressed: _help,
                            soft: true,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _controlButton(
                            key: const Key('next_step_button'),
                            label: '次へ',
                            icon: Icons.arrow_forward,
                            onPressed: busy || index == steps.length - 1
                                ? null
                                : () => _move(index + 1),
                            filled: true,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
