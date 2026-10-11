import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/kitchen_timer.dart';

class KitchenTimerSnapshot {
  KitchenTimerSnapshot({
    required this.bootId,
    required Iterable<KitchenTimer> timers,
  }) : timers = List.unmodifiable(timers) {
    if (bootId.trim().isEmpty ||
        this.timers.map((t) => t.id).toSet().length != this.timers.length) {
      throw const FormatException('Invalid timer snapshot identity.');
    }
  }
  final String bootId;
  final List<KitchenTimer> timers;

  factory KitchenTimerSnapshot.decode(String source) {
    final data = jsonDecode(source);
    if (data is! Map<String, dynamic> ||
        data['storage_version'] is! int ||
        data['storage_version'] != 1 ||
        data['boot_id'] is! String ||
        data['timers'] is! List) {
      throw const FormatException('Unsupported timer snapshot.');
    }
    return KitchenTimerSnapshot(
      bootId: data['boot_id'] as String,
      timers: (data['timers'] as List).map((entry) {
        if (entry is! Map<String, dynamic>) {
          throw const FormatException('Invalid timer.');
        }
        return KitchenTimer.fromStorage(entry);
      }),
    );
  }

  String encode() => jsonEncode({
    'storage_version': 1,
    'boot_id': bootId,
    'timers': timers.map((t) => t.toStorage()).toList(),
  });

  bool requiresRebootReview(String currentBootId) => bootId != currentBootId;

  List<KitchenTimer> restore({
    required String currentBootId,
    required Duration now,
  }) {
    if (requiresRebootReview(currentBootId)) {
      throw StateError('Device reboot requires explicit review.');
    }
    return List.unmodifiable(
      timers.map((timer) {
        if (now < timer.updatedAt) {
          throw StateError('Monotonic clock moved backwards.');
        }
        return timer.state == KitchenTimerState.running &&
                now >= timer.deadline!
            ? timer.reachDeadline(now: now)
            : timer;
      }),
    );
  }
}

/// Serial atomic snapshots. A corrupt primary is never replaced by empty data.
class KitchenTimerFileStore {
  KitchenTimerFileStore(this.file);
  final File file;
  Future<void> _tail = Future.value();
  File get _backup => File('${file.path}.bak');
  File get _temporary => File('${file.path}.tmp');

  Future<T> _serial<T>(Future<T> Function() operation) {
    final previous = _tail;
    final complete = Completer<void>();
    _tail = complete.future;
    return () async {
      await previous;
      try {
        return await operation();
      } finally {
        complete.complete();
      }
    }();
  }

  Future<KitchenTimerSnapshot?> load() => _serial(_load);

  Future<KitchenTimerSnapshot?> _load() async {
    final File source;
    if (await file.exists()) {
      source = file;
    } else if (await _backup.exists()) {
      source = _backup;
    } else {
      if (await _temporary.exists()) {
        throw const FormatException(
          'Interrupted first timer save requires recovery.',
        );
      }
      return null;
    }
    return KitchenTimerSnapshot.decode(await source.readAsString());
  }

  Future<void> save(KitchenTimerSnapshot snapshot) => _serial(() async {
    final payload = snapshot.encode();
    KitchenTimerSnapshot.decode(payload);
    await _load(); // Fail closed on corruption or an unknown existing version.
    await file.parent.create(recursive: true);
    await _temporary.writeAsString(payload, flush: true);
    if (await file.exists()) {
      if (await _backup.exists()) await _backup.delete();
      await file.rename(_backup.path);
    }
    try {
      await _temporary.rename(file.path);
    } catch (_) {
      if (!await file.exists() && await _backup.exists()) {
        await _backup.copy(file.path);
      }
      rethrow;
    }
    // Retain the previous committed snapshot as a recovery backup.
  });
}
