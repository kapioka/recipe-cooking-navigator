import 'dart:convert';
import 'dart:io';

/// Local UI progress and completed sessions; never modifies Recipe documents.
class CookingStore {
  CookingStore([this.file]);
  final File? file;
  Map<String, dynamic> _memory = {
    'storage_version': 1,
    'help_seen': false,
    'progress': <String, dynamic>{},
    'sessions': <Map<String, dynamic>>[],
  };
  Future<void> _pending = Future.value();

  Future<Map<String, dynamic>> read() async {
    await _pending;
    return _read();
  }

  Future<Map<String, dynamic>> _read() async {
    if (file == null) {
      return jsonDecode(jsonEncode(_memory)) as Map<String, dynamic>;
    }
    final backup = File('${file!.path}.bak');
    final interrupted = File('${file!.path}.previous');
    final candidates = [file!, backup, interrupted];
    FormatException? invalidData;
    for (final candidate in candidates) {
      if (!await candidate.exists()) {
        continue;
      }
      try {
        return await _readFile(candidate);
      } on FormatException catch (error) {
        invalidData = error;
      }
    }
    if (invalidData != null) {
      throw invalidData;
    }
    return {
      'storage_version': 1,
      'help_seen': false,
      'progress': <String, dynamic>{},
      'sessions': <Map<String, dynamic>>[],
    };
  }

  Future<Map<String, dynamic>> _readFile(File source) async {
    final dynamic data;
    try {
      data = jsonDecode(await source.readAsString());
    } on FormatException {
      throw const FormatException('調理位置の保存形式を読み込めません。');
    }
    if (data is! Map<String, dynamic> ||
        data['storage_version'] != 1 ||
        data['help_seen'] != null && data['help_seen'] is! bool ||
        data['progress'] is! Map<String, dynamic> ||
        data['sessions'] is! List) {
      throw const FormatException('調理位置の保存形式を読み込めません。');
    }
    for (final entry in (data['progress'] as Map<String, dynamic>).entries) {
      final p = entry.value;
      if (p is! Map ||
          p['recipe_id'] != entry.key ||
          p['revision'] is! int ||
          p['revision'] < 1 ||
          p['step_id'] is! String ||
          p['step_id'].isEmpty ||
          p['started_at'] is! String ||
          DateTime.tryParse(p['started_at']) == null ||
          p['updated_at'] is! String ||
          DateTime.tryParse(p['updated_at']) == null) {
        throw const FormatException('調理位置が破損しています。');
      }
    }
    for (final session in data['sessions'] as List) {
      if (session is! Map ||
          session['session_id'] is! String ||
          session['session_id'].isEmpty ||
          session['recipe_id'] is! String ||
          session['recipe_id'].isEmpty ||
          session['revision'] is! int ||
          session['revision'] < 1 ||
          session['started_at'] is! String ||
          DateTime.tryParse(session['started_at']) == null ||
          session['completed_at'] is! String ||
          DateTime.tryParse(session['completed_at']) == null) {
        throw const FormatException('調理履歴が破損しています。');
      }
    }
    return data;
  }

  Future<void> savePosition(
    String id,
    int revision,
    String stepId, {
    bool restart = false,
  }) {
    if (id.isEmpty || revision < 1 || stepId.isEmpty) {
      return Future.error(const FormatException('保存する調理位置が正しくありません。'));
    }
    return _update((data) {
      final progress = data['progress'] as Map<String, dynamic>;
      final previous = progress[id] as Map?;
      final now = DateTime.now().toUtc().toIso8601String();
      progress[id] = {
        'recipe_id': id,
        'revision': revision,
        'step_id': stepId,
        'started_at': !restart && previous != null
            ? previous['started_at']
            : now,
        'updated_at': now,
      };
    });
  }

  Future<void> complete(String id, int revision) => _update((data) {
    final progress = data['progress'] as Map<String, dynamic>;
    final previous = progress[id] as Map?;
    if (previous == null || previous['revision'] != revision) {
      throw const FormatException('調理位置を確認できないため完了を保存できません。');
    }
    (data['sessions'] as List).add({
      'session_id': '${id}_${DateTime.now().microsecondsSinceEpoch}',
      'recipe_id': id,
      'revision': revision,
      'started_at': previous['started_at'],
      'completed_at': DateTime.now().toUtc().toIso8601String(),
    });
    progress.remove(id);
  });

  Future<void> markHelpSeen() => _update((data) {
    data['help_seen'] = true;
  });

  Future<void> _update(void Function(Map<String, dynamic>) change) {
    final result = _pending.then((_) async {
      final data = await _read();
      change(data);
      if (file == null) {
        _memory = data;
        return;
      }
      final target = file!;
      final temp = File('${target.path}.tmp');
      final backup = File('${target.path}.bak');
      final previous = File('${target.path}.previous');
      await target.parent.create(recursive: true);
      await temp.writeAsString(jsonEncode(data), flush: true);
      if (await target.exists()) {
        if (await previous.exists()) {
          await previous.delete();
        }
        await target.rename(previous.path);
      }
      try {
        await temp.rename(target.path);
      } catch (_) {
        if (!await target.exists() && await previous.exists()) {
          await previous.rename(target.path);
        }
        rethrow;
      }
      try {
        await target.copy(backup.path);
        if (await previous.exists()) {
          await previous.delete();
        }
      } on FileSystemException {
        // The new primary file is already committed. Keep either recovery file
        // rather than reporting a false save failure for cleanup only.
      }
    });
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
