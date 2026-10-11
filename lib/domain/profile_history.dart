import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'cooking_profile.dart';
import 'feedback_validator.dart';
import 'preference_candidate.dart';
import 'preference_evidence.dart';
import 'preference_operation.dart';
import 'recipe_document.dart';

String profileDigest(CookingProfile profile) => sha256
    .convert(utf8.encode(canonicalPreferenceJson(profile.toJson())))
    .toString();

String historyRecordDigest(ProfileHistoryRecord record) => sha256
    .convert(utf8.encode(canonicalPreferenceJson(record.toJson())))
    .toString();

/// Immutable Drive record. Digests detect corruption, not signer identity.
class ProfileHistoryRecord {
  ProfileHistoryRecord._(
    this._json,
    this.base,
    this.result,
    this.operation,
    this.evidence,
  );
  final Map<String, dynamic> _json;
  final CookingProfile? base;
  final CookingProfile result;
  final PreferenceOperation? operation;
  final List<PreferenceEvidence> evidence;
  String get id => _json['record_id'] as String;
  String? get parentId => _json['parent_id'] as String?;
  Map<String, dynamic> toJson() => RecipeDocument.copyJson(_json);

  factory ProfileHistoryRecord.bootstrap(
    CookingProfile profile, {
    required String id,
    required FeedbackValidator validator,
  }) => ProfileHistoryRecord.fromJson({
    'history_schema_version': '1.0.0',
    'type': 'profile_history',
    'record_id': id,
    'kind': 'bootstrap',
    'parent_id': null,
    'parent_digest': null,
    'base_profile': null,
    'base_digest': null,
    'result_profile': profile.toJson(),
    'result_digest': profileDigest(profile),
    'operation': null,
    'evidence': <Object>[],
  }, validator);

  factory ProfileHistoryRecord.update(
    ProfileHistoryRecord parent,
    PreferenceOperation operation, {
    required FeedbackValidator validator,
    Iterable<PreferenceEvidence> evidence = const [],
    List<PreferenceCandidate> previous = const [],
  }) {
    final rows = evidence.toList();
    final next = operation.apply(parent.result, rows, previous);
    return ProfileHistoryRecord.fromJson({
      'history_schema_version': '1.0.0',
      'type': 'profile_history',
      'record_id': operation.id,
      'kind': 'update',
      'parent_id': parent.id,
      'parent_digest': historyRecordDigest(parent),
      'base_profile': parent.result.toJson(),
      'base_digest': profileDigest(parent.result),
      'result_profile': next.toJson(),
      'result_digest': profileDigest(next),
      'operation': operation.toJson(),
      'evidence': rows.map((e) => e.toJson()).toList(),
    }, validator);
  }

  factory ProfileHistoryRecord.fromJson(
    Map<String, dynamic> json,
    FeedbackValidator validator,
  ) {
    const keys = {
      'history_schema_version',
      'type',
      'record_id',
      'kind',
      'parent_id',
      'parent_digest',
      'base_profile',
      'base_digest',
      'result_profile',
      'result_digest',
      'operation',
      'evidence',
    };
    if (json.length != keys.length ||
        json.keys.toSet().difference(keys).isNotEmpty ||
        json['history_schema_version'] != '1.0.0' ||
        json['type'] != 'profile_history' ||
        json['record_id'] is! String ||
        (json['record_id'] as String).trim().isEmpty ||
        !{'bootstrap', 'update'}.contains(json['kind']) ||
        json['result_profile'] is! Map<String, dynamic> ||
        json['evidence'] is! List) {
      throw const FormatException('Profile履歴の形式が正しくありません。');
    }
    final result = CookingProfile.fromJson(
      json['result_profile'] as Map<String, dynamic>,
    );
    if (json['result_digest'] != profileDigest(result)) {
      throw const FormatException('Profile履歴の内容とdigestが一致しません。');
    }
    final rows = (json['evidence'] as List)
        .map(
          (e) => PreferenceEvidence.fromJson(
            Map<String, dynamic>.from(e as Map),
            validator,
          ),
        )
        .toList();
    CookingProfile? base;
    PreferenceOperation? operation;
    if (json['kind'] == 'bootstrap') {
      if (json['parent_id'] != null ||
          json['parent_digest'] != null ||
          json['base_profile'] != null ||
          json['base_digest'] != null ||
          json['operation'] != null ||
          rows.isNotEmpty) {
        throw const FormatException('Profile履歴の開始記録が正しくありません。');
      }
    } else {
      if (json['parent_digest'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$')
              .hasMatch(json['parent_digest'] as String) ||
          json['parent_id'] is! String ||
          (json['parent_id'] as String).trim().isEmpty ||
          json['base_profile'] is! Map<String, dynamic> ||
          json['operation'] is! Map<String, dynamic>) {
        throw const FormatException('Profile履歴の更新元が欠けています。');
      }
      base = CookingProfile.fromJson(
        json['base_profile'] as Map<String, dynamic>,
      );
      operation = PreferenceOperation.fromJson(
        json['operation'] as Map<String, dynamic>,
      );
      if (json['base_digest'] != profileDigest(base) ||
          base.id != result.id ||
          result.revision != base.revision + 1 ||
          operation.id != json['record_id'] ||
          operation.baseRevision != base.revision ||
          !operation.changesProfile ||
          rows.map((e) => e.id).toSet().length != rows.length ||
          (operation.decision == null && rows.isNotEmpty) ||
          (operation.decision != null &&
              (rows.length != operation.decision!.evidenceIds.length ||
                  !rows
                      .map((e) => e.id)
                      .toSet()
                      .containsAll(operation.decision!.evidenceIds)))) {
        throw const FormatException('Profile履歴の操作と更新元が一致しません。');
      }
    }
    return ProfileHistoryRecord._(
      RecipeDocument.copyJson(json),
      base,
      result,
      operation,
      List.unmodifiable(rows),
    );
  }
}

class ProfileHistory {
  ProfileHistory._(this.records);
  final List<ProfileHistoryRecord> records;
  ProfileHistoryRecord get head => records.last;

  /// Requires the complete observed set. A branch/orphan is never resolved by
  /// revision number or timestamp. The caller retains its last valid cache.
  factory ProfileHistory.validate(Iterable<ProfileHistoryRecord> input) {
    final byId = <String, ProfileHistoryRecord>{};
    for (final record in input) {
      final old = byId[record.id];
      if (old != null &&
          canonicalPreferenceJson(old.toJson()) !=
              canonicalPreferenceJson(record.toJson())) {
        throw const FormatException('同じ履歴IDに異なる内容があります。');
      }
      byId[record.id] = record;
    }
    if (byId.isEmpty ||
        byId.length > 100 ||
        byId.values.map((r) => r.result.id).toSet().length != 1) {
      throw const FormatException('Profile履歴が空・上限超過または複数Profileです。');
    }
    final roots = byId.values.where((r) => r.parentId == null).toList();
    if (roots.length != 1) {
      throw const FormatException('Profile履歴の開始記録が競合または欠落しています。');
    }
    final children = <String, ProfileHistoryRecord>{};
    for (final record in byId.values.where((r) => r.parentId != null)) {
      if (!byId.containsKey(record.parentId) ||
          children.containsKey(record.parentId)) {
        throw const FormatException(
          'Profile履歴に分岐または更新元の欠落があります。両方の履歴を保持して停止します。',
        );
      }
      children[record.parentId!] = record;
    }
    final ordered = <ProfileHistoryRecord>[roots.single];
    final decisions = <PreferenceCandidate>[];
    final evidence = <String, PreferenceEvidence>{};
    var current = roots.single;
    while (children.containsKey(current.id)) {
      final next = children[current.id]!;
      if (next._json['parent_digest'] != historyRecordDigest(current) ||
          canonicalPreferenceJson(next.base!.toJson()) !=
              canonicalPreferenceJson(current.result.toJson())) {
        throw const FormatException('Profile履歴の更新元の内容が一致しません。');
      }
      for (final row in next.evidence) {
        final old = evidence[row.id];
        if (old != null &&
            canonicalPreferenceJson(old.toJson()) !=
                canonicalPreferenceJson(row.toJson())) {
          throw const FormatException('履歴の根拠Feedbackが競合しています。');
        }
        evidence[row.id] = row;
      }
      const PreferenceCandidateEngine().propose(
        evidence.values,
        scope: PreferenceScope(PreferenceScopeKind.global, '*'),
      );
      final replay = next.operation!.apply(
        current.result,
        next.evidence,
        decisions,
      );
      if (canonicalPreferenceJson(replay.toJson()) !=
          canonicalPreferenceJson(next.result.toJson())) {
        throw const FormatException('Profile履歴の操作と更新後の内容が一致しません。');
      }
      if (next.operation!.decision != null) {
        decisions.add(next.operation!.decision!);
      }
      ordered.add(next);
      current = next;
    }
    if (ordered.length != byId.length) {
      throw const FormatException('Profile履歴に未接続・循環した記録があります。');
    }
    return ProfileHistory._(List.unmodifiable(ordered));
  }
}
