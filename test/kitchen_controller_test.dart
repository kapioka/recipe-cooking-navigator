import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_cooking_navigator/application/kitchen_controller.dart';
import 'package:recipe_cooking_navigator/data/kitchen_timer_store.dart';
import 'package:recipe_cooking_navigator/domain/kitchen_timer.dart';

void main() {
  late Duration clock;
  late KitchenController kitchen;
  setUp(() {
    clock = Duration.zero;
    kitchen = KitchenController(now: () => clock)..open(foreground: true);
  });
  tearDown(() => kitchen.dispose());

  test('preset buttons configure a ready timer until explicit start', () {
    final id = kitchen.createReady(
      name: 'タイマー',
      duration: const Duration(seconds: 10),
    );
    kitchen.addConfiguredDuration(id, const Duration(minutes: 1));
    kitchen.addConfiguredDuration(id, const Duration(minutes: 10));
    final ready = kitchen.timers.single;
    expect(ready.state, KitchenTimerState.ready);
    expect(ready.configuredDuration, const Duration(minutes: 11, seconds: 10));
    expect(ready.deadline, isNull);
    final restored = KitchenTimer.fromStorage(ready.toStorage());
    expect(restored.configuredDuration, ready.configuredDuration);
    expect(restored.state, KitchenTimerState.ready);
    kitchen.start(id);
    expect(kitchen.timers.single.state, KitchenTimerState.running);
    expect(
      kitchen.timers.single.deadline,
      const Duration(minutes: 11, seconds: 10),
    );
  });

  test('clearing a ready preset allows a different time before starting', () {
    final id = kitchen.createReady(
      name: 'タイマー',
      duration: const Duration(minutes: 10),
    );
    kitchen.addConfiguredDuration(id, const Duration(minutes: 1));
    kitchen.remove(id);
    expect(kitchen.timers, isEmpty);

    final replacement = kitchen.createReady(
      name: 'タイマー',
      duration: const Duration(seconds: 10),
    );
    expect(kitchen.timers.single.id, replacement);
    expect(
      kitchen.timers.single.configuredDuration,
      const Duration(seconds: 10),
    );
    expect(kitchen.timers.single.state, KitchenTimerState.ready);
  });

  test('save must succeed before a transaction becomes visible', () async {
    final saved = Completer<void>();
    final started = Completer<void>();
    final future = kitchen.transact(
      (k) => k.create(name: '保存', duration: const Duration(minutes: 1)),
      (timers) {
        started.complete();
        return saved.future;
      },
    );
    await started.future;
    expect(kitchen.timers, isEmpty);
    kitchen.setForeground(false);
    saved.complete();
    await future;
    expect(kitchen.timers.single.name, '保存');
    expect(kitchen.shouldKeepAwake, isFalse);
  });

  test('failed persistence preserves all prior timer state', () async {
    final id = kitchen.create(
      name: '保存済み',
      duration: const Duration(minutes: 1),
    );
    final original = kitchen.timers.single;
    await expectLater(
      kitchen.transact((k) => k.cancel(id), (_) async {
        throw StateError('disk failure');
      }),
      throwsStateError,
    );
    expect(kitchen.timers.single, same(original));
    expect(kitchen.isOpen, isTrue);
  });

  test('queued transactions accumulate instead of overwriting', () async {
    final saved = <int>[];
    Future<void> save(List<KitchenTimer> timers) async {
      saved.add(timers.length);
    }

    await Future.wait([
      kitchen.transact(
        (k) => k.create(name: 'A', duration: const Duration(seconds: 1)),
        save,
      ),
      kitchen.transact(
        (k) => k.create(name: 'B', duration: const Duration(seconds: 2)),
        save,
      ),
    ]);
    expect(saved, [1, 2]);
    expect(kitchen.timers.map((t) => t.name), ['A', 'B']);
  });

  test('unchanged ticks do not cause disk writes', () async {
    kitchen.create(name: 'timer', duration: const Duration(minutes: 1));
    var writes = 0;
    Future<void> save(List<KitchenTimer> _) async {
      writes++;
    }

    await kitchen.transact((k) => k.refresh(), save);
    expect(writes, 0);
    clock = const Duration(minutes: 2);
    await kitchen.transact((k) => k.refresh(), save);
    await kitchen.transact((k) => k.refresh(), save);
    expect(writes, 1);
  });

  String create({String name = 'パスタ', int seconds = 60}) => kitchen.create(
    name: name,
    duration: Duration(seconds: seconds),
  );
  KitchenTimer timer(String id) =>
      kitchen.timers.singleWhere((t) => t.id == id);

  test('ticks and foreground changes cannot shift a deadline', () {
    final id = create();
    final deadline = timer(id).deadline;
    for (var i = 0; i < 10; i++) {
      kitchen.refresh();
    }
    expect(timer(id).deadline, deadline);
    kitchen.setForeground(false);
    expect(kitchen.shouldKeepAwake, isFalse);
    clock = const Duration(seconds: 80);
    kitchen.setForeground(true);
    kitchen.refresh();
    expect(kitchen.shouldKeepAwake, isTrue);
    expect(timer(id).state, KitchenTimerState.finished);
    expect(timer(id).isFinishedAcknowledged, isFalse);
    kitchen.acknowledge(id);
    kitchen.refresh();
    expect(timer(id).state, KitchenTimerState.finished);
    expect(timer(id).isFinishedAcknowledged, isTrue);
  });

  test('independent IDs keep paused and running timers separate', () {
    final first = create();
    final second = create(name: 'ソース', seconds: 120);
    clock = const Duration(seconds: 10);
    kitchen.pause(first);
    kitchen.extend(second, const Duration(seconds: 30));
    clock = const Duration(seconds: 30);
    kitchen.resume(first);
    expect(timer(first).deadline, const Duration(seconds: 80));
    expect(timer(second).deadline, const Duration(seconds: 150));
    expect(() => kitchen.timers.clear(), throwsUnsupportedError);
  });

  test('recipe step timers retain source identity outside recipe state', () {
    final id = kitchen.createRecipeStep(
      recipeId: 'recipe-1',
      recipeRevision: 3,
      recipeDisplayName: 'カレー',
      stepId: 'step-simmer',
      stepDisplayName: '煮込む',
      duration: const Duration(minutes: 8),
    );
    final created = timer(id);
    expect(created.name, 'カレー・煮込む');
    expect(created.state, KitchenTimerState.running);
    expect(created.configuredDuration, const Duration(minutes: 8));
    final source = created.source as RecipeStepTimerSource;
    expect(source.recipeId, 'recipe-1');
    expect(source.recipeRevision, 3);
    expect(source.stepId, 'step-simmer');
    expect(source.recipeDisplayName, 'カレー');
    expect(source.stepDisplayName, '煮込む');
  });

  test('a pause or extension racing expiry preserves completion', () {
    final first = create(seconds: 1);
    final second = create(seconds: 1);
    clock = const Duration(seconds: 1);
    kitchen.pause(first);
    kitchen.extend(second, const Duration(seconds: 60));
    expect(timer(first).state, KitchenTimerState.finished);
    expect(timer(second).state, KitchenTimerState.finished);
    expect(timer(second).notificationGeneration, 1);
  });

  test('exit refuses active timers until cancellation is explicit', () {
    final first = create();
    final second = create(seconds: 90);
    kitchen.pause(second);
    expect(kitchen.close(), isFalse);
    expect(kitchen.isOpen, isTrue);
    expect(kitchen.close(mode: KitchenCloseMode.stopTimers), isTrue);
    expect(kitchen.shouldKeepAwake, isFalse);
    expect(timer(first).state, KitchenTimerState.cancelled);
    expect(timer(second).state, KitchenTimerState.cancelled);
    clock = const Duration(days: 1);
    kitchen.refresh();
    expect(timer(first).state, KitchenTimerState.cancelled);
    expect(() => create(), throwsStateError);
  });

  test('continue exit closes Kitchen without changing active timers', () {
    final id = create();
    final before = timer(id);
    expect(kitchen.close(mode: KitchenCloseMode.continueTimers), isTrue);
    expect(kitchen.isOpen, isFalse);
    expect(kitchen.shouldKeepAwake, isFalse);
    expect(timer(id), same(before));
    expect(timer(id).state, KitchenTimerState.running);
  });

  test('acknowledgement and reset require explicit restart', () {
    final id = create(seconds: 1);
    expect(() => kitchen.remove(id), throwsStateError);
    clock = const Duration(seconds: 1);
    kitchen.refresh();
    expect(() => kitchen.remove(id), throwsStateError);
    kitchen.acknowledge(id);
    kitchen.reset(id);
    expect(timer(id).state, KitchenTimerState.ready);
    expect(timer(id).isFinishedAcknowledged, isFalse);
    clock = const Duration(minutes: 1);
    kitchen.start(id);
    expect(timer(id).deadline, const Duration(seconds: 61));
    kitchen.cancel(id);
    kitchen.remove(id);
    expect(kitchen.timers, isEmpty);
  });

  test('invalid replacement and invalid creation preserve prior state', () {
    final id = create();
    final original = timer(id);
    final store = KitchenTimerStore()..replaceAll([original]);
    expect(() => store.replaceAll([original, original]), throwsArgumentError);
    expect(store.timers.single, same(original));
    expect(() => create(name: ' '), throwsArgumentError);
    expect(() => create(seconds: 0), throwsArgumentError);
    expect(kitchen.timers.single, same(original));
  });

  test('new controller with an existing store never reuses an ID', () {
    final store = KitchenTimerStore();
    final first = KitchenController(now: () => clock, store: store)
      ..open(foreground: true);
    final firstId = first.create(
      name: '1',
      duration: const Duration(seconds: 1),
    );
    first.dispose();
    final second = KitchenController(now: () => clock, store: store)
      ..open(foreground: true);
    addTearDown(second.dispose);
    final secondId = second.create(
      name: '2',
      duration: const Duration(seconds: 2),
    );
    expect(firstId, isNot(secondId));
    expect(second.timers.length, 2);
  });
}
