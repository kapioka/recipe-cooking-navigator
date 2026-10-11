import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_cooking_navigator/domain/kitchen_timer.dart';

void main() {
  KitchenTimer standaloneTimer({
    String id = 'timer-1',
    String name = 'ゆで時間',
    Duration duration = const Duration(minutes: 2),
  }) {
    return KitchenTimer.create(
      id: id,
      name: name,
      configuredDuration: duration,
      source: const KitchenTimerSource.standalone(),
      now: Duration.zero,
    );
  }

  test('start, elapsed time, pause, and resume use monotonic time', () {
    final ready = standaloneTimer();
    final running = ready.start(now: const Duration(seconds: 10));

    expect(running.state, KitchenTimerState.running);
    expect(running.deadline, const Duration(seconds: 130));
    expect(
      running.remainingAt(now: const Duration(seconds: 40)),
      const Duration(seconds: 90),
    );

    final paused = running.pause(now: const Duration(seconds: 40));
    expect(paused.state, KitchenTimerState.paused);
    expect(paused.deadline, isNull);
    expect(paused.pausedRemaining, const Duration(seconds: 90));

    final resumed = paused.resume(now: const Duration(seconds: 50));
    expect(resumed.state, KitchenTimerState.running);
    expect(resumed.deadline, const Duration(seconds: 140));
    expect(resumed.pausedRemaining, isNull);
    expect(resumed.notificationGeneration, 3);
  });

  test('deadline arrival finishes exactly at the deadline', () {
    final running = standaloneTimer(duration: const Duration(seconds: 30))
        .start(now: const Duration(seconds: 5));

    expect(
      () => running.reachDeadline(now: const Duration(seconds: 34)),
      throwsStateError,
    );

    final finished = running.reachDeadline(now: const Duration(seconds: 35));
    expect(finished.state, KitchenTimerState.finished);
    expect(
      finished.remainingAt(now: const Duration(seconds: 35)),
      Duration.zero,
    );
    expect(finished.deadline, isNull);
    expect(finished.notificationGeneration, running.notificationGeneration);
  });

  test('acknowledging completion keeps the timer finished', () {
    final finished = standaloneTimer(duration: const Duration(seconds: 10))
        .start(now: Duration.zero)
        .reachDeadline(now: const Duration(seconds: 10));

    final acknowledged = finished.acknowledgeFinished(
      now: const Duration(seconds: 11),
    );

    expect(acknowledged.state, KitchenTimerState.finished);
    expect(acknowledged.isFinishedAcknowledged, isTrue);
    expect(acknowledged.finishedAcknowledgedAt, const Duration(seconds: 11));
    expect(
      acknowledged.notificationGeneration,
      finished.notificationGeneration,
    );
  });

  test('extension and cancellation invalidate older notification work', () {
    final running = standaloneTimer(duration: const Duration(minutes: 1))
        .start(now: Duration.zero);
    final extended = running.extend(
      by: const Duration(seconds: 30),
      now: const Duration(seconds: 10),
    );

    expect(extended.deadline, const Duration(seconds: 90));
    expect(extended.configuredDuration, const Duration(minutes: 1));
    expect(extended.notificationGeneration, 2);

    final cancelled = extended.cancel(now: const Duration(seconds: 20));
    expect(cancelled.state, KitchenTimerState.cancelled);
    expect(cancelled.deadline, isNull);
    expect(cancelled.notificationGeneration, 3);
  });

  test('multiple timers change independently', () {
    final first = standaloneTimer(
      id: 'timer-a',
      name: 'パスタ',
    ).start(now: Duration.zero);
    final second = standaloneTimer(
      id: 'timer-b',
      name: 'ソース',
      duration: const Duration(minutes: 5),
    ).start(now: Duration.zero);

    final pausedFirst = first.pause(now: const Duration(seconds: 15));

    expect(pausedFirst.state, KitchenTimerState.paused);
    expect(second.state, KitchenTimerState.running);
    expect(second.deadline, const Duration(minutes: 5));
    expect(second.notificationGeneration, 1);
  });

  test('recipe-step source retains identifiers without RecipeDocument', () {
    final source = KitchenTimerSource.recipeStep(
      recipeId: 'recipe-1',
      recipeRevision: 2,
      stepId: 'step-3',
      recipeDisplayName: 'カレー',
      stepDisplayName: '煮込む',
    ) as RecipeStepTimerSource;
    final timer = KitchenTimer.create(
      id: 'timer-recipe',
      name: 'カレー・煮込む',
      configuredDuration: const Duration(minutes: 20),
      source: source,
      now: Duration.zero,
    );

    expect(timer.source, same(source));
    expect(source.recipeId, 'recipe-1');
    expect(source.recipeRevision, 2);
    expect(source.stepId, 'step-3');
    expect(source.recipeDisplayName, 'カレー');
    expect(source.stepDisplayName, '煮込む');
  });

  test('invalid inputs and transitions fail without changing the timer', () {
    expect(
      () => KitchenTimer.create(
        id: ' ',
        name: 'name',
        configuredDuration: const Duration(seconds: 1),
        source: const KitchenTimerSource.standalone(),
        now: Duration.zero,
      ),
      throwsArgumentError,
    );
    expect(() => standaloneTimer(name: ' '), throwsArgumentError);
    expect(() => standaloneTimer(duration: Duration.zero), throwsArgumentError);
    expect(
      () => KitchenTimerSource.recipeStep(
        recipeId: 'recipe-1',
        recipeRevision: 0,
        stepId: 'step-1',
        recipeDisplayName: '料理',
        stepDisplayName: '工程',
      ),
      throwsArgumentError,
    );

    final ready = standaloneTimer();
    expect(() => ready.pause(now: Duration.zero), throwsStateError);
    expect(() => ready.cancel(now: Duration.zero), throwsStateError);
    expect(
      () => ready.extend(by: const Duration(seconds: 1), now: Duration.zero),
      throwsStateError,
    );
    expect(ready.state, KitchenTimerState.ready);
    expect(ready.notificationGeneration, 0);

    final running = ready.start(now: const Duration(seconds: 1));
    expect(
      () => running.pause(now: const Duration(seconds: 121)),
      throwsStateError,
    );
    expect(
      () => running.extend(by: Duration.zero, now: const Duration(seconds: 2)),
      throwsArgumentError,
    );
    expect(() => running.pause(now: Duration.zero), throwsArgumentError);
    expect(running.state, KitchenTimerState.running);
    expect(running.deadline, const Duration(seconds: 121));
    expect(running.notificationGeneration, 1);
  });

  test(
    'reset restores the original setting and permits an explicit restart',
    () {
      final extended = standaloneTimer(duration: const Duration(minutes: 1))
          .start(now: Duration.zero)
          .extend(
            by: const Duration(minutes: 10),
            now: const Duration(seconds: 1),
          );

      final reset = extended.reset(now: const Duration(seconds: 2));

      expect(reset.state, KitchenTimerState.ready);
      expect(reset.configuredDuration, const Duration(minutes: 1));
      expect(
        reset.remainingAt(now: const Duration(seconds: 2)),
        const Duration(minutes: 1),
      );
      expect(reset.deadline, isNull);
      expect(reset.pausedRemaining, isNull);
      expect(reset.notificationGeneration, 3);

      final restarted = reset.start(now: const Duration(seconds: 3));
      expect(restarted.deadline, const Duration(seconds: 63));
      expect(restarted.notificationGeneration, 4);
    },
  );
}
