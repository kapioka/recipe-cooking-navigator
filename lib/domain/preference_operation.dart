import 'cooking_profile.dart';
import 'preference_candidate.dart';
import 'preference_evidence.dart';
import 'recipe_document.dart';

/// Ordered user decisions. Rejections have no Profile delta; legacy rejection
/// times remain unknown rather than being invented during migration.
class PreferenceOperation {
  PreferenceOperation._(this._json);

  factory PreferenceOperation.candidate(
    PreferenceCandidate decision, {
    required String id,
    required int baseRevision,
    DateTime? now,
  }) => PreferenceOperation.fromJson({
    'operation_schema_version': '1.0.0',
    'operation_id': id,
    'kind': 'candidate',
    'base_revision': baseRevision,
    'decided_at': now?.toUtc().toIso8601String(),
    'candidate': decision.toJson(),
  });

  factory PreferenceOperation.explicit({
    required String id,
    required int baseRevision,
    required DateTime now,
    required PreferenceScope scope,
    required String dimension,
    required int direction,
    required String declaration,
  }) => PreferenceOperation.fromJson({
    'operation_schema_version': '1.0.0',
    'operation_id': id,
    'kind': 'explicit_preference',
    'base_revision': baseRevision,
    'decided_at': now.toUtc().toIso8601String(),
    'scope': scope.toJson(),
    'dimension': dimension,
    'direction': direction,
    'declaration': declaration.trim(),
  });

  factory PreferenceOperation.fromJson(Map<String, dynamic> json) {
    final candidate = json['kind'] == 'candidate';
    final allowed = {
      'operation_schema_version',
      'operation_id',
      'kind',
      'base_revision',
      'decided_at',
      if (candidate)
        'candidate'
      else ...[
        'scope',
        'dimension',
        'direction',
        'declaration',
      ],
    };
    if (json.keys.toSet().difference(allowed).isNotEmpty ||
        json.length != allowed.length ||
        json['operation_schema_version'] != '1.0.0' ||
        json['operation_id'] is! String ||
        (json['operation_id'] as String).trim().isEmpty ||
        !{'candidate', 'explicit_preference'}.contains(json['kind']) ||
        json['base_revision'] is! int ||
        (json['base_revision'] as int) < 1 ||
        (json['decided_at'] != null &&
            (json['decided_at'] is! String ||
                DateTime.tryParse(json['decided_at'] as String)?.isUtc !=
                    true))) {
      throw const FormatException('好みの操作履歴が正しくありません。');
    }
    final operation = PreferenceOperation._(RecipeDocument.copyJson(json));
    if (candidate) {
      if (json['candidate'] is! Map<String, dynamic> ||
          operation.decision!.status == PreferenceCandidateStatus.proposed ||
          (json['decided_at'] == null &&
              operation.decision!.status !=
                  PreferenceCandidateStatus.rejected)) {
        throw const FormatException('好みの決定履歴が正しくありません。');
      }
    } else {
      if (json['decided_at'] == null ||
          json['scope'] is! Map<String, dynamic> ||
          json['dimension'] is! String ||
          json['direction'] is! int ||
          json['declaration'] is! String) {
        throw const FormatException('明示登録の操作履歴が正しくありません。');
      }
      // The Profile domain validates all scope, dimension and declaration rules.
      operation.apply(
        CookingProfile.create(
          'validation',
          DateTime.parse(json['decided_at'] as String),
        ),
        const [],
        const [],
        checkRevision: false,
      );
    }
    return operation;
  }

  final Map<String, dynamic> _json;
  String get id => _json['operation_id'] as String;
  int get baseRevision => _json['base_revision'] as int;
  PreferenceCandidate? get decision => _json['kind'] == 'candidate'
      ? PreferenceCandidate.fromJson(_json['candidate'] as Map<String, dynamic>)
      : null;
  bool get changesProfile =>
      decision?.status != PreferenceCandidateStatus.rejected;
  Map<String, dynamic> toJson() => RecipeDocument.copyJson(_json);

  CookingProfile apply(
    CookingProfile profile,
    Iterable<PreferenceEvidence> evidence,
    List<PreferenceCandidate> previous, {
    bool checkRevision = true,
  }) {
    if (checkRevision && profile.revision != baseRevision) {
      throw const FormatException('好みの操作履歴の更新元が一致しません。');
    }
    final time = _json['decided_at'] == null
        ? null
        : DateTime.parse(_json['decided_at'] as String);
    if (time != null &&
        time.isBefore(
          DateTime.parse(profile.toJson()['updated_at'] as String),
        )) {
      throw const FormatException('好みの操作日時が更新元より前です。');
    }
    final candidate = decision;
    if (candidate == null) {
      final raw = _json['scope'] as Map<String, dynamic>;
      final kind = PreferenceScopeKind.values
          .where((e) => e.name == raw['kind'])
          .firstOrNull;
      if (raw.length != 2 || kind == null || raw['value'] is! String) {
        throw const FormatException('明示登録の適用範囲が正しくありません。');
      }
      return profile.registerExplicit(
        scope: PreferenceScope(kind, raw['value'] as String),
        dimension: _json['dimension'] as String,
        direction: _json['direction'] as int,
        declaration: _json['declaration'] as String,
        expectedRevision: profile.revision,
        now: time!,
      );
    }
    final ids = candidate.evidenceIds.toSet();
    final rows = evidence.where((e) => ids.contains(e.id)).toList();
    final proposed = candidate.toJson()..['status'] = 'proposed';
    final candidates = const PreferenceCandidateEngine().propose(
      rows,
      scope: candidate.scope,
      previous: previous,
    );
    if (rows.length != ids.length ||
        !candidates.any(
          (c) =>
              canonicalPreferenceJson(c.toJson()) ==
              canonicalPreferenceJson(proposed),
        )) {
      throw const FormatException('保存された候補の根拠と集計結果が一致しません。');
    }
    return changesProfile
        ? profile.accept(
            PreferenceCandidate.fromJson(proposed),
            expectedRevision: profile.revision,
            now: time!,
          )
        : profile;
  }
}
