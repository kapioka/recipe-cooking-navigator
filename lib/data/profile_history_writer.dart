import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/cooking_profile.dart';
import '../domain/feedback_validator.dart';
import '../domain/preference_evidence.dart';
import '../domain/profile_history.dart';
import '../platform/feedback_archive_platform.dart';

class PendingProfileWrite {
  const PendingProfileWrite(this.root, this.record);
  final String root;
  final ProfileHistoryRecord record;
}

/// Durable single pending intent, scoped to the selected Drive connection.
/// An uncertain provider result must retry this exact record, never a new ID.
class ProfileHistoryWriter {
  ProfileHistoryWriter(this.file, this.validator, this.archive);
  final File file;
  final FeedbackValidator validator;
  final FeedbackArchivePlatform archive;
  static final _queues = <String, Future<void>>{};
  Future<T> _serialized<T>(Future<T> Function() action) async {
    final key = file.absolute.path.toLowerCase();
    final prior = _queues[key] ?? Future<void>.value();
    final done = Completer<void>();
    _queues[key] = done.future;
    await prior;
    try {
      return await action();
    } finally {
      done.complete();
      if (identical(_queues[key], done.future)) _queues.remove(key);
    }
  }

  Future<PendingProfileWrite?> pending() => _serialized(_pending);
  Future<PendingProfileWrite?> _pending() async {
    final source = await file.exists() ? file : File('${file.path}.bak');
    if (!await source.exists()) {
      if (await File('${file.path}.tmp').exists()) {
        throw const FormatException('好みの送信記録に保存中断データがあります。');
      }
      return null;
    }
    if (await source.length() > 2 * 1024 * 1024) {
      throw const FormatException('好みの送信記録が上限を超えています。');
    }
    final json = jsonDecode(await source.readAsString());
    if (json is! Map<String, dynamic> ||
        json.length != 2 ||
        json['storage_version'] != 1 ||
        !json.containsKey('pending')) {
      throw const FormatException('好みの送信記録が破損または未対応です。');
    }
    if (json['pending'] == null) return null;
    final value = json['pending'];
    if (value is! Map<String, dynamic> ||
        value.length != 2 ||
        value['root'] is! String ||
        Uri.tryParse(value['root'] as String)?.scheme != 'content' ||
        value['record'] is! Map<String, dynamic>) {
      throw const FormatException('好みの送信先と履歴が正しくありません。');
    }
    return PendingProfileWrite(
      value['root'] as String,
      ProfileHistoryRecord.fromJson(
        value['record'] as Map<String, dynamic>,
        validator,
      ),
    );
  }

  Future<void> _write(PendingProfileWrite? value) async {
    final data = jsonEncode({
      'storage_version': 1,
      'pending': value == null
          ? null
          : {'root': value.root, 'record': value.record.toJson()},
    });
    final temp = File('${file.path}.tmp');
    final backup = File('${file.path}.bak');
    await file.parent.create(recursive: true);
    await temp.writeAsString(data, flush: true);
    if (await file.exists()) {
      if (await backup.exists()) await backup.delete();
      await file.rename(backup.path);
    }
    try {
      await temp.rename(file.path);
    } catch (_) {
      if (!await file.exists() && await backup.exists()) {
        await backup.rename(file.path);
      }
      rethrow;
    }
  }

  Future<ProfileHistory?> read(String root) async {
    final items = await archive.readHistory(root);
    if (items.isEmpty) return null;
    return ProfileHistory.validate(
      items.map((item) {
        if (item.source == null) {
          throw const FormatException('Profile履歴を読み込めません。');
        }
        final json = jsonDecode(item.source!);
        if (json is! Map<String, dynamic>) {
          throw const FormatException('Profile履歴の形式が正しくありません。');
        }
        return ProfileHistoryRecord.fromJson(json, validator);
      }),
    );
  }

  Future<ProfileHistory> commit(
    String root,
    ProfileHistoryRecord record,
  ) => _serialized(() async {
    if (Uri.tryParse(root)?.scheme != 'content' ||
        utf8.encode(canonicalPreferenceJson(record.toJson())).length >
            1024 * 1024) {
      throw const FormatException('好みの送信先またはサイズが正しくありません。');
    }
    final old = await _pending();
    if (old != null &&
        (old.root != root ||
            canonicalPreferenceJson(old.record.toJson()) !=
                canonicalPreferenceJson(record.toJson()))) {
      throw StateError('確認待ちの送信記録があります。先に同じ更新を再確認してください。');
    }
    final current = await read(root);
    final observed = current?.records
        .where((r) => r.id == record.id)
        .firstOrNull;
    if (observed != null) {
      if (canonicalPreferenceJson(observed.toJson()) !=
          canonicalPreferenceJson(record.toJson())) {
        throw StateError('同じ履歴IDの内容が競合しています。上書きしません。');
      }
      return current!;
    }
    if (record.parentId == null) {
      if (current != null) throw StateError('Driveの履歴が既に開始されています。再読込してください。');
      final legacySource = await archive.readProfile(root);
      if (legacySource != null) {
        final legacy = CookingProfile.fromJson(
          jsonDecode(legacySource) as Map<String, dynamic>,
        );
        if (canonicalPreferenceJson(legacy.toJson()) !=
            canonicalPreferenceJson(record.result.toJson())) {
          throw StateError('移行元のDriveの好みが変更されています。再読込してください。');
        }
      } else if (record.result.revision != 1 ||
          (record.result.toJson()['preferences'] as List).isNotEmpty ||
          (record.result.toJson()['explicit_constraints'] as List).isNotEmpty) {
        throw StateError('移行元がないDriveでは空の好みから履歴を開始してください。');
      }
      ProfileHistory.validate([record]);
    } else {
      if (current == null || current.head.id != record.parentId) {
        throw StateError('Driveの更新元が変更されています。再読込してください。');
      }
      ProfileHistory.validate([...current.records, record]);
    }
    if (old == null) await _write(PendingProfileWrite(root, record));
    await archive.appendHistory(root, record);
    final verified = await read(root);
    final written = verified?.records
        .where((r) => r.id == record.id)
        .firstOrNull;
    if (written == null ||
        canonicalPreferenceJson(written.toJson()) !=
            canonicalPreferenceJson(record.toJson())) {
      throw StateError('Driveの保存結果をまだ確認できません。同じ更新を再確認してください。');
    }
    return verified!;
  });

  /// Called only after the verified result has also been cached successfully.
  Future<void> acknowledge(String root, String recordId) =>
      _serialized(() async {
        final value = await _pending();
        if (value == null) return;
        if (value.root != root || value.record.id != recordId) {
          throw StateError('確認対象の送信記録が変わっています。');
        }
        await _write(null);
      });
}
