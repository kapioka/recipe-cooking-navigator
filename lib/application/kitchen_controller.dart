import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/kitchen_timer_store.dart';
import '../domain/kitchen_timer.dart';

enum KitchenCloseMode { requireInactive, stopTimers, continueTimers }

class KitchenController extends ChangeNotifier {
  KitchenController({required this.now, KitchenTimerStore? store})
    : _store = store ?? KitchenTimerStore();

  final Duration Function() now;
  final KitchenTimerStore _store;
  int _nextId = 0;
  Future<void> _transactionTail = Future.value();
  bool _disposed = false;
  bool isOpen = false;
  bool isForeground = false;

  List<KitchenTimer> get timers => _store.timers;

  void refreshDisplay() => notifyListeners();

  void restoreTimers(Iterable<KitchenTimer> timers) {
    _store.replaceAll(timers);
    notifyListeners();
  }

  /// Publish only after persistence succeeds. Tick-only reads do not write.
  Future<T> transact<T>(
    T Function(KitchenController) operation,
    Future<void> Function(List<KitchenTimer>) save,
  ) async {
    final previous = _transactionTail;
    final completed = Completer<void>();
    _transactionTail = completed.future;
    await previous;
    final working =
        KitchenController(
            now: now,
            store: KitchenTimerStore()..replaceAll(timers),
          )
          .._nextId = _nextId
          ..isOpen = isOpen
          ..isForeground = isForeground;
    try {
      final result = operation(working);
      if (!listEquals(timers, working.timers)) await save(working.timers);
      _store.replaceAll(working.timers);
      _nextId = working._nextId;
      // Lifecycle may have suspended the real session while save was pending.
      if (!working.isOpen) {
        isOpen = false;
        isForeground = false;
      }
      if (!_disposed) notifyListeners();
      return result;
    } finally {
      working.dispose();
      completed.complete();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  bool get shouldKeepAwake => isOpen && isForeground;
  bool get hasActiveTimers => timers.any(
    (timer) =>
        timer.state == KitchenTimerState.running ||
        timer.state == KitchenTimerState.paused,
  );

  void open({required bool foreground}) {
    isOpen = true;
    isForeground = foreground;
    notifyListeners();
  }

  void setForeground(bool foreground) {
    isForeground = foreground;
    notifyListeners();
  }

  String create({required String name, required Duration duration}) {
    return _create(
      name: name,
      duration: duration,
      source: const KitchenTimerSource.standalone(),
    );
  }

  String createReady({required String name, required Duration duration}) {
    if (!isOpen) throw StateError('Open the kitchen before creating a timer.');
    final time = now();
    String id;
    do {
      id = 'kitchen-${++_nextId}';
    } while (timers.any((timer) => timer.id == id));
    _store.replaceAll([
      ...timers,
      KitchenTimer.create(
        id: id,
        name: name.trim(),
        configuredDuration: duration,
        source: const KitchenTimerSource.standalone(),
        now: time,
      ),
    ]);
    notifyListeners();
    return id;
  }

  String createRecipeStep({
    required String recipeId,
    required int recipeRevision,
    required String recipeDisplayName,
    required String stepId,
    required String stepDisplayName,
    required Duration duration,
  }) {
    return _create(
      name: '$recipeDisplayName・$stepDisplayName',
      duration: duration,
      source: KitchenTimerSource.recipeStep(
        recipeId: recipeId,
        recipeRevision: recipeRevision,
        stepId: stepId,
        recipeDisplayName: recipeDisplayName,
        stepDisplayName: stepDisplayName,
      ),
    );
  }

  String _create({
    required String name,
    required Duration duration,
    required KitchenTimerSource source,
  }) {
    if (!isOpen) throw StateError('Open the kitchen before creating a timer.');
    final time = now();
    String id;
    do {
      id = 'kitchen-${++_nextId}';
    } while (timers.any((timer) => timer.id == id));
    final timer = KitchenTimer.create(
      id: id,
      name: name.trim(),
      configuredDuration: duration,
      source: source,
      now: time,
    ).start(now: time);
    _store.replaceAll([...timers, timer]);
    notifyListeners();
    return id;
  }

  void refresh() {
    final time = now();
    _store.replaceAll(timers.map((timer) => _settle(timer, time)));
    notifyListeners();
  }

  KitchenTimer _settle(KitchenTimer timer, Duration time) =>
      timer.state == KitchenTimerState.running && time >= timer.deadline!
      ? timer.reachDeadline(now: time)
      : timer;

  void _change(
    String id,
    KitchenTimer Function(KitchenTimer, Duration) action,
  ) {
    final time = now();
    if (!timers.any((timer) => timer.id == id)) {
      throw StateError('Unknown timer: $id');
    }
    _store.replaceAll(
      timers.map(
        (timer) => timer.id == id
            ? action(_settle(timer, time), time)
            : _settle(timer, time),
      ),
    );
    notifyListeners();
  }

  // A tap racing the deadline must preserve completion, not revive a timer.
  void pause(String id) => _change(
    id,
    (timer, time) => timer.state == KitchenTimerState.finished
        ? timer
        : timer.pause(now: time),
  );
  void resume(String id) =>
      _change(id, (timer, time) => timer.resume(now: time));
  void start(String id) => _change(id, (timer, time) => timer.start(now: time));
  void reset(String id) => _change(id, (timer, time) => timer.reset(now: time));
  void cancel(String id) => _change(
    id,
    (timer, time) => timer.state == KitchenTimerState.finished
        ? timer
        : timer.cancel(now: time),
  );
  void acknowledge(String id) =>
      _change(id, (timer, time) => timer.acknowledgeFinished(now: time));
  void extend(String id, Duration duration) => _change(
    id,
    (timer, time) => timer.state == KitchenTimerState.finished
        ? timer
        : timer.extend(by: duration, now: time),
  );
  void addConfiguredDuration(String id, Duration duration) => _change(
    id,
    (timer, time) => timer.addConfiguredDuration(by: duration, now: time),
  );

  void remove(String id) {
    final timer = timers.firstWhere((timer) => timer.id == id);
    if (timer.state == KitchenTimerState.running ||
        timer.state == KitchenTimerState.paused ||
        (timer.state == KitchenTimerState.finished &&
            !timer.isFinishedAcknowledged)) {
      throw StateError('Stop or acknowledge the timer before removing it.');
    }
    _store.replaceAll(timers.where((timer) => timer.id != id));
    notifyListeners();
  }

  bool close({KitchenCloseMode mode = KitchenCloseMode.requireInactive}) {
    refresh();
    if (hasActiveTimers && mode == KitchenCloseMode.requireInactive) {
      return false;
    }
    final time = now();
    _store.replaceAll(
      timers.map(
        (timer) =>
            mode == KitchenCloseMode.stopTimers &&
                (timer.state == KitchenTimerState.running ||
                    timer.state == KitchenTimerState.paused)
            ? timer.cancel(now: time)
            : timer,
      ),
    );
    isOpen = false;
    isForeground = false;
    notifyListeners();
    return true;
  }
}
