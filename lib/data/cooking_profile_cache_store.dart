import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:json_schema/json_schema.dart';

import '../domain/cooking_profile.dart';
import '../domain/preference_evidence.dart';

class CachedCookingProfile {
  const CachedCookingProfile(
    this.root,
    this.profile, {
    this.historyRecordId,
    this.historyRecordDigest,
  });
  final String root;
  final CookingProfile profile;
  final String? historyRecordId;
  final String? historyRecordDigest;
}

/// Last validated remote state. Never replaces the local approval history.
class CookingProfileCacheStore {
  CookingProfileCacheStore(
    this.file,
    String schemaSource, {
    String? explicitSchemaSource,
  }) : _schemas = [
         for (final source in [schemaSource, ?explicitSchemaSource])
           JsonSchema.create(source, schemaVersion: SchemaVersion.draft2020_12),
       ];
  final File file;
  final List<JsonSchema> _schemas;
  static final _queues = <String, Future<void>>{};

  Future<T> _serialized<T>(Future<T> Function() action) async {
    final key = file.absolute.path.toLowerCase();
    final previous = _queues[key] ?? Future<void>.value();
    final done = Completer<void>();
    _queues[key] = done.future;
    await previous;
    try {
      return await action();
    } finally {
      done.complete();
      if (identical(_queues[key], done.future)) _queues.remove(key);
    }
  }

  CookingProfile _validate(Object? json) {
    if (json is! Map<String, dynamic> ||
        !_schemas.any((schema) => schema.validate(json).isValid)) {
      throw const FormatException('Driveの好みの形式が破損または未対応です。');
    }
    return CookingProfile.fromJson(json);
  }

  Future<CachedCookingProfile?> load() => _serialized(_load);

  Future<CachedCookingProfile?> _load() async {
    final source = await file.exists() ? file : File('${file.path}.bak');
    if (!await source.exists()) {
      if (await File('${file.path}.tmp').exists()) {
        throw const FormatException('好みのキャッシュに保存中断データがあります。');
      }
      return null;
    }
    if (await source.length() > 2 * 1024 * 1024) {
      throw const FormatException('Profileキャッシュが読込上限を超えています。');
    }
    final json = jsonDecode(await source.readAsString());
    if (json is! Map<String, dynamic> ||
        !{1, 2, 3}.contains(json['storage_version']) ||
        json.length !=
            (json['storage_version'] == 1
                ? 3
                : json['storage_version'] == 2
                ? 4
                : 5) ||
        (json['storage_version'] != 1 &&
            (json['history_record_id'] is! String ||
                (json['history_record_id'] as String).trim().isEmpty)) ||
        (json['storage_version'] == 3 &&
            (json['history_record_digest'] is! String ||
                !RegExp(r'^[a-f0-9]{64}$')
                    .hasMatch(json['history_record_digest'] as String))) ||
        json['root'] is! String ||
        Uri.tryParse(json['root'] as String)?.scheme != 'content') {
      throw const FormatException('好みのキャッシュが破損または未対応です。');
    }
    return CachedCookingProfile(
      json['root'] as String,
      _validate(json['profile']),
      historyRecordId: json['history_record_id'] as String?,
      historyRecordDigest: json['history_record_digest'] as String?,
    );
  }

  Future<CachedCookingProfile> save(
    String root,
    String source, {
    String? historyRecordId,
    String? historyRecordDigest,
  }) => _serialized(() async {
    if (historyRecordId != null && historyRecordId.trim().isEmpty) {
      throw const FormatException('Profile履歴IDが正しくありません。');
    }
    if (historyRecordDigest != null &&
        (historyRecordId == null ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(historyRecordDigest))) {
      throw const FormatException('Profile履歴のdigestが正しくありません。');
    }
    if (Uri.tryParse(root)?.scheme != 'content') {
      throw const FormatException('Profileの保存元が正しくありません。');
    }
    if (utf8.encode(source).length > 1024 * 1024) {
      throw const FormatException('Profileファイルの上限は1 MBです。');
    }
    final profile = _validate(jsonDecode(source));
    final previous = await _load();
    if (previous != null && previous.root == root) {
      if (previous.historyRecordId != null && historyRecordId == null) {
        throw StateError('検証済みのProfile履歴が見つかりません。配布用コピーへ切り替えません。');
      }
      if (previous.historyRecordDigest != null &&
          (historyRecordDigest == null ||
              (previous.historyRecordId == historyRecordId &&
                  previous.historyRecordDigest != historyRecordDigest))) {
        throw StateError('以前に確認したProfile履歴の内容が変わっています。既存の記録を保持します。');
      }
      final old = previous.profile;
      if (old.id != profile.id ||
          profile.revision < old.revision ||
          DateTime.parse(profile.toJson()['updated_at'] as String)
              .isBefore(DateTime.parse(old.toJson()['updated_at'] as String))) {
        throw StateError('DriveのProfile ID・更新番号・日時が以前の記録と一致しません。');
      }
      if (old.revision == profile.revision) {
        if (canonicalPreferenceJson(old.toJson()) !=
            canonicalPreferenceJson(profile.toJson())) {
          throw StateError('同じProfile更新番号に異なる内容があります。既存の記録を保持しています。');
        }
        if (previous.historyRecordId == historyRecordId &&
            previous.historyRecordDigest == historyRecordDigest) {
          return previous;
        }
        if (previous.historyRecordId != null &&
            previous.historyRecordId != historyRecordId) {
          throw StateError('同じProfile更新番号の履歴IDが変わっています。');
        }
      }
    }
    final next = CachedCookingProfile(
      root,
      profile,
      historyRecordId: historyRecordId,
      historyRecordDigest: historyRecordDigest,
    );
    final temp = File('${file.path}.tmp');
    final backup = File('${file.path}.bak');
    await file.parent.create(recursive: true);
    await temp.writeAsString(
      jsonEncode({
        'storage_version': historyRecordId == null
            ? 1
            : historyRecordDigest == null
            ? 2
            : 3,
        'history_record_id': ?historyRecordId,
        'history_record_digest': ?historyRecordDigest,
        'root': root,
        'profile': profile.toJson(),
      }),
      flush: true,
    );
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
    return next;
  });
}
