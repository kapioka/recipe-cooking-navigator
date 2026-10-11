enum KitchenTimerState { ready, running, paused, finished, cancelled }

sealed class KitchenTimerSource {
  const KitchenTimerSource._();

  const factory KitchenTimerSource.standalone() = StandaloneTimerSource;

  factory KitchenTimerSource.recipeStep({
    required String recipeId,
    required int recipeRevision,
    required String stepId,
    required String recipeDisplayName,
    required String stepDisplayName,
  }) = RecipeStepTimerSource;
}

final class StandaloneTimerSource extends KitchenTimerSource {
  const StandaloneTimerSource() : super._();
}

final class RecipeStepTimerSource extends KitchenTimerSource {
  factory RecipeStepTimerSource({
    required String recipeId,
    required int recipeRevision,
    required String stepId,
    required String recipeDisplayName,
    required String stepDisplayName,
  }) {
    _requireNonBlank(recipeId, 'recipeId');
    if (recipeRevision <= 0) {
      throw ArgumentError.value(
        recipeRevision,
        'recipeRevision',
        'must be greater than zero',
      );
    }
    _requireNonBlank(stepId, 'stepId');
    _requireNonBlank(recipeDisplayName, 'recipeDisplayName');
    _requireNonBlank(stepDisplayName, 'stepDisplayName');

    return RecipeStepTimerSource._(
      recipeId: recipeId,
      recipeRevision: recipeRevision,
      stepId: stepId,
      recipeDisplayName: recipeDisplayName,
      stepDisplayName: stepDisplayName,
    );
  }

  const RecipeStepTimerSource._({
    required this.recipeId,
    required this.recipeRevision,
    required this.stepId,
    required this.recipeDisplayName,
    required this.stepDisplayName,
  }) : super._();

  final String recipeId;
  final int recipeRevision;
  final String stepId;
  final String recipeDisplayName;
  final String stepDisplayName;
}

final class KitchenTimer {
  factory KitchenTimer.fromStorage(Map<String, dynamic> data) {
    int number(String key, {bool positive = false}) {
      final value = data[key];
      if (value is! int || value < (positive ? 1 : 0)) {
        throw FormatException('Invalid timer field: $key');
      }
      return value;
    }

    String text(String key) {
      final value = data[key];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('Invalid timer field: $key');
      }
      return value;
    }

    Duration? optionalTime(String key) =>
        data[key] == null ? null : Duration(microseconds: number(key));
    final state = KitchenTimerState.values
        .where((s) => s.name == data['state'])
        .singleOrNull;
    final sourceData = data['source'];
    if (state == null || sourceData is! Map<String, dynamic>) {
      throw const FormatException('Invalid timer state or source.');
    }
    final KitchenTimerSource source;
    if (sourceData['kind'] == 'standalone') {
      source = const KitchenTimerSource.standalone();
    } else if (sourceData['kind'] == 'recipe_step') {
      if (sourceData['recipe_id'] is! String ||
          sourceData['revision'] is! int ||
          sourceData['step_id'] is! String ||
          sourceData['recipe_name'] is! String ||
          sourceData['step_name'] is! String) {
        throw const FormatException('Invalid recipe timer source.');
      }
      source = KitchenTimerSource.recipeStep(
        recipeId: sourceData['recipe_id'] as String,
        recipeRevision: sourceData['revision'] as int,
        stepId: sourceData['step_id'] as String,
        recipeDisplayName: sourceData['recipe_name'] as String,
        stepDisplayName: sourceData['step_name'] as String,
      );
    } else {
      throw const FormatException('Unknown timer source.');
    }
    final created = Duration(microseconds: number('created_us'));
    final updated = Duration(microseconds: number('updated_us'));
    final deadline = optionalTime('deadline_us');
    final paused = optionalTime('paused_us');
    final acknowledged = optionalTime('acknowledged_us');
    if (updated < created ||
        (state == KitchenTimerState.running
            ? deadline == null || deadline <= updated
            : deadline != null) ||
        (state == KitchenTimerState.paused
            ? paused == null || paused <= Duration.zero
            : paused != null) ||
        (acknowledged != null &&
            (state != KitchenTimerState.finished ||
                acknowledged < created ||
                acknowledged > updated))) {
      throw const FormatException('Inconsistent timer state.');
    }
    return KitchenTimer._(
      id: text('id'),
      name: text('name'),
      configuredDuration: Duration(
        microseconds: number('duration_us', positive: true),
      ),
      source: source,
      state: state,
      deadline: deadline,
      pausedRemaining: paused,
      notificationGeneration: number('generation'),
      createdAt: created,
      updatedAt: updated,
      finishedAcknowledgedAt: acknowledged,
    );
  }

  Map<String, dynamic> toStorage() => {
    'id': id,
    'name': name,
    'duration_us': configuredDuration.inMicroseconds,
    'source': switch (source) {
      StandaloneTimerSource() => {'kind': 'standalone'},
      RecipeStepTimerSource s => {
        'kind': 'recipe_step',
        'recipe_id': s.recipeId,
        'revision': s.recipeRevision,
        'step_id': s.stepId,
        'recipe_name': s.recipeDisplayName,
        'step_name': s.stepDisplayName,
      },
    },
    'state': state.name,
    'deadline_us': deadline?.inMicroseconds,
    'paused_us': pausedRemaining?.inMicroseconds,
    'generation': notificationGeneration,
    'created_us': createdAt.inMicroseconds,
    'updated_us': updatedAt.inMicroseconds,
    'acknowledged_us': finishedAcknowledgedAt?.inMicroseconds,
  };

  /// Only after explicit confirmation of an OS reboot; never restarts a timer.
  KitchenTimer stopAfterReboot({required Duration now}) {
    _requireNonNegativeTime(now);
    return KitchenTimer._(
      id: id,
      name: name,
      configuredDuration: configuredDuration,
      source: source,
      state:
          state == KitchenTimerState.running ||
              state == KitchenTimerState.paused
          ? KitchenTimerState.cancelled
          : state,
      deadline: null,
      pausedRemaining: null,
      notificationGeneration: notificationGeneration + 1,
      createdAt: now,
      updatedAt: now,
      finishedAcknowledgedAt: isFinishedAcknowledged ? now : null,
    );
  }

  factory KitchenTimer.create({
    required String id,
    required String name,
    required Duration configuredDuration,
    required KitchenTimerSource source,
    required Duration now,
  }) {
    _requireNonBlank(id, 'id');
    _requireNonBlank(name, 'name');
    _requirePositiveDuration(configuredDuration, 'configuredDuration');
    _requireNonNegativeTime(now);

    return KitchenTimer._(
      id: id,
      name: name,
      configuredDuration: configuredDuration,
      source: source,
      state: KitchenTimerState.ready,
      deadline: null,
      pausedRemaining: null,
      notificationGeneration: 0,
      createdAt: now,
      updatedAt: now,
      finishedAcknowledgedAt: null,
    );
  }

  const KitchenTimer._({
    required this.id,
    required this.name,
    required this.configuredDuration,
    required this.source,
    required this.state,
    required this.deadline,
    required this.pausedRemaining,
    required this.notificationGeneration,
    required this.createdAt,
    required this.updatedAt,
    required this.finishedAcknowledgedAt,
  });

  final String id;
  final String name;
  final Duration configuredDuration;
  final KitchenTimerSource source;
  final KitchenTimerState state;

  /// The monotonic deadline. Present only while [state] is running.
  final Duration? deadline;

  /// The retained remaining time. Present only while [state] is paused.
  final Duration? pausedRemaining;

  /// Invalidates notification work created for an earlier measurement.
  final int notificationGeneration;

  final Duration createdAt;
  final Duration updatedAt;

  /// Confirmation is independent from the finished state.
  final Duration? finishedAcknowledgedAt;

  bool get isFinishedAcknowledged => finishedAcknowledgedAt != null;

  Duration remainingAt({required Duration now}) {
    _validateNow(now);
    return switch (state) {
      KitchenTimerState.ready => configuredDuration,
      KitchenTimerState.running => _nonNegative(deadline! - now),
      KitchenTimerState.paused => pausedRemaining!,
      KitchenTimerState.finished ||
      KitchenTimerState.cancelled => Duration.zero,
    };
  }

  KitchenTimer start({required Duration now}) {
    _requireState(KitchenTimerState.ready, 'start');
    _validateNow(now);
    return _replace(
      state: KitchenTimerState.running,
      deadline: now + configuredDuration,
      notificationGeneration: notificationGeneration + 1,
      updatedAt: now,
    );
  }

  KitchenTimer pause({required Duration now}) {
    _requireState(KitchenTimerState.running, 'pause');
    _validateNow(now);
    final remaining = deadline! - now;
    if (remaining <= Duration.zero) {
      throw StateError('Cannot pause a timer whose deadline has arrived.');
    }
    return _replace(
      state: KitchenTimerState.paused,
      clearDeadline: true,
      pausedRemaining: remaining,
      notificationGeneration: notificationGeneration + 1,
      updatedAt: now,
    );
  }

  KitchenTimer resume({required Duration now}) {
    _requireState(KitchenTimerState.paused, 'resume');
    _validateNow(now);
    return _replace(
      state: KitchenTimerState.running,
      deadline: now + pausedRemaining!,
      clearPausedRemaining: true,
      notificationGeneration: notificationGeneration + 1,
      updatedAt: now,
    );
  }

  KitchenTimer extend({required Duration by, required Duration now}) {
    _requirePositiveDuration(by, 'by');
    _validateNow(now);

    switch (state) {
      case KitchenTimerState.running:
        if (now >= deadline!) {
          throw StateError('Cannot extend a timer whose deadline has arrived.');
        }
        return _replace(
          deadline: deadline! + by,
          notificationGeneration: notificationGeneration + 1,
          updatedAt: now,
        );
      case KitchenTimerState.paused:
        return _replace(
          pausedRemaining: pausedRemaining! + by,
          notificationGeneration: notificationGeneration + 1,
          updatedAt: now,
        );
      case KitchenTimerState.ready:
      case KitchenTimerState.finished:
      case KitchenTimerState.cancelled:
        throw StateError('Cannot extend a timer in the $state state.');
    }
  }

  KitchenTimer addConfiguredDuration({
    required Duration by,
    required Duration now,
  }) {
    _requireState(KitchenTimerState.ready, 'adjust');
    _requirePositiveDuration(by, 'by');
    _validateNow(now);
    return KitchenTimer._(
      id: id,
      name: name,
      configuredDuration: configuredDuration + by,
      source: source,
      state: state,
      deadline: null,
      pausedRemaining: null,
      notificationGeneration: notificationGeneration,
      createdAt: createdAt,
      updatedAt: now,
      finishedAcknowledgedAt: null,
    );
  }

  KitchenTimer reset({required Duration now}) {
    if (state == KitchenTimerState.ready) {
      throw StateError('Cannot reset a timer in the ready state.');
    }
    _validateNow(now);
    return _replace(
      state: KitchenTimerState.ready,
      clearDeadline: true,
      clearPausedRemaining: true,
      clearFinishedAcknowledgedAt: true,
      notificationGeneration: notificationGeneration + 1,
      updatedAt: now,
    );
  }

  KitchenTimer cancel({required Duration now}) {
    if (state != KitchenTimerState.running &&
        state != KitchenTimerState.paused) {
      throw StateError('Cannot cancel a timer in the $state state.');
    }
    _validateNow(now);
    return _replace(
      state: KitchenTimerState.cancelled,
      clearDeadline: true,
      clearPausedRemaining: true,
      notificationGeneration: notificationGeneration + 1,
      updatedAt: now,
    );
  }

  KitchenTimer reachDeadline({required Duration now}) {
    _requireState(KitchenTimerState.running, 'reach its deadline');
    _validateNow(now);
    if (now < deadline!) {
      throw StateError('Cannot finish a timer before its deadline.');
    }
    return _replace(
      state: KitchenTimerState.finished,
      clearDeadline: true,
      updatedAt: now,
    );
  }

  KitchenTimer acknowledgeFinished({required Duration now}) {
    _requireState(KitchenTimerState.finished, 'acknowledge completion for');
    _validateNow(now);
    if (isFinishedAcknowledged) {
      throw StateError('Timer completion has already been acknowledged.');
    }
    return _replace(finishedAcknowledgedAt: now, updatedAt: now);
  }

  KitchenTimer _replace({
    KitchenTimerState? state,
    Duration? deadline,
    bool clearDeadline = false,
    Duration? pausedRemaining,
    bool clearPausedRemaining = false,
    int? notificationGeneration,
    Duration? updatedAt,
    Duration? finishedAcknowledgedAt,
    bool clearFinishedAcknowledgedAt = false,
  }) {
    return KitchenTimer._(
      id: id,
      name: name,
      configuredDuration: configuredDuration,
      source: source,
      state: state ?? this.state,
      deadline: clearDeadline ? null : deadline ?? this.deadline,
      pausedRemaining: clearPausedRemaining
          ? null
          : pausedRemaining ?? this.pausedRemaining,
      notificationGeneration:
          notificationGeneration ?? this.notificationGeneration,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      finishedAcknowledgedAt: clearFinishedAcknowledgedAt
          ? null
          : finishedAcknowledgedAt ?? this.finishedAcknowledgedAt,
    );
  }

  void _requireState(KitchenTimerState expected, String operation) {
    if (state != expected) {
      throw StateError('Cannot $operation a timer in the $state state.');
    }
  }

  void _validateNow(Duration now) {
    _requireNonNegativeTime(now);
    if (now < updatedAt) {
      throw ArgumentError.value(
        now,
        'now',
        'must not move backwards from $updatedAt',
      );
    }
  }
}

void _requireNonBlank(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be blank');
  }
}

void _requirePositiveDuration(Duration value, String name) {
  if (value <= Duration.zero) {
    throw ArgumentError.value(value, name, 'must be greater than zero');
  }
}

void _requireNonNegativeTime(Duration now) {
  if (now.isNegative) {
    throw ArgumentError.value(now, 'now', 'must not be negative');
  }
}

Duration _nonNegative(Duration value) {
  return value.isNegative ? Duration.zero : value;
}
