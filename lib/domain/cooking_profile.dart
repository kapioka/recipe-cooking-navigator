import 'preference_candidate.dart';
import 'recipe_document.dart';
import 'session_assessment.dart';

class CookingProfile {
  CookingProfile._(this._json);

  factory CookingProfile.create(String id, DateTime now) =>
      CookingProfile.fromJson({
        'profile_schema_version': '1.0.0',
        'type': 'cooking_profile',
        'profile_id': id,
        'revision': 1,
        'updated_at': now.toUtc().toIso8601String(),
        'preferences': <Object>[],
        'explicit_constraints': <String>[],
      });

  factory CookingProfile.fromJson(Map<String, dynamic> json) {
    const keys = {
      'profile_schema_version',
      'type',
      'profile_id',
      'revision',
      'updated_at',
      'preferences',
      'explicit_constraints',
    };
    if (json.length != keys.length ||
        json.keys.toSet().difference(keys).isNotEmpty ||
        !{'1.0.0', '1.1.0'}.contains(json['profile_schema_version']) ||
        json['type'] != 'cooking_profile' ||
        json['profile_id'] is! String ||
        (json['profile_id'] as String).trim().isEmpty ||
        json['revision'] is! int ||
        (json['revision'] as int) < 1 ||
        json['updated_at'] is! String ||
        DateTime.tryParse(json['updated_at'] as String)?.isUtc != true ||
        json['preferences'] is! List ||
        json['explicit_constraints'] is! List ||
        (json['explicit_constraints'] as List).any(
          (e) => e is! String || e.trim().isEmpty,
        )) {
      throw const FormatException('Cooking Profileの形式が正しくありません。');
    }
    final seen = <String>{};
    final extended = json['profile_schema_version'] == '1.1.0';
    for (final p in json['preferences'] as List) {
      final explicit =
          p is Map && extended && p['source_kind'] == 'explicit_user';
      if (p is! Map<String, dynamic> ||
          p.length !=
              (explicit
                  ? 6
                  : extended
                  ? 7
                  : 6) ||
          (extended &&
              !{'feedback', 'explicit_user'}.contains(p['source_kind'])) ||
          !SessionAssessment.tasteDimensions.contains(p['dimension']) ||
          p['direction'] is! int ||
          !{-1, 1}.contains(p['direction']) ||
          p['scope'] is! Map<String, dynamic> ||
          (!explicit &&
              (p['rules_version'] != PreferenceCandidate.rulesVersion ||
                  p['feedback_ids'] is! List ||
                  (p['feedback_ids'] as List).isEmpty ||
                  (p['feedback_ids'] as List).any(
                    (e) => e is! String || e.trim().isEmpty,
                  ) ||
                  (p['feedback_ids'] as List).toSet().length !=
                      (p['feedback_ids'] as List).length)) ||
          (explicit &&
              (p['declaration'] is! String ||
                  (p['declaration'] as String).trim().isEmpty ||
                  (p['declaration'] as String).length > 2000)) ||
          p['confirmed_at'] is! String ||
          DateTime.tryParse(p['confirmed_at'] as String)?.isUtc != true) {
        throw const FormatException('確定Preferenceの形式が正しくありません。');
      }
      final scope = p['scope'] as Map<String, dynamic>;
      if (scope.length != 2 ||
          !PreferenceScopeKind.values
              .map((e) => e.name)
              .contains(scope['kind']) ||
          scope['value'] is! String ||
          (scope['value'] as String).trim().isEmpty ||
          (scope['kind'] == 'global' && scope['value'] != '*') ||
          !seen.add('${scope['kind']}:${scope['value']}:${p['dimension']}')) {
        throw const FormatException('Preferenceの適用範囲が不正または重複しています。');
      }
    }
    return CookingProfile._(RecipeDocument.copyJson(json));
  }

  final Map<String, dynamic> _json;
  String get id => _json['profile_id'] as String;
  int get revision => _json['revision'] as int;
  Map<String, dynamic> toJson() => RecipeDocument.copyJson(_json);

  /// The caller must invoke this only in response to the user's acceptance.
  CookingProfile accept(
    PreferenceCandidate candidate, {
    required int expectedRevision,
    required DateTime now,
  }) {
    if (expectedRevision != revision) {
      throw StateError('Profileが更新されています。再読込してください。');
    }
    if (candidate.status != PreferenceCandidateStatus.proposed) {
      throw StateError('提案中の候補だけを承認できます。');
    }
    if (now.isBefore(DateTime.parse(_json['updated_at'] as String))) {
      throw ArgumentError('Profile time moved backwards.');
    }
    final next = toJson();
    final preferences = next['preferences'] as List;
    preferences.removeWhere(
      (p) =>
          p['dimension'] == candidate.dimension &&
          p['scope']['kind'] == candidate.scope.kind.name &&
          p['scope']['value'] == candidate.scope.value,
    );
    preferences.add({
      'scope': candidate.scope.toJson(),
      'dimension': candidate.dimension,
      'direction': candidate.direction,
      'rules_version': PreferenceCandidate.rulesVersion,
      'feedback_ids': candidate.evidenceIds,
      'confirmed_at': now.toUtc().toIso8601String(),
      if (next['profile_schema_version'] == '1.1.0') 'source_kind': 'feedback',
    });
    next['revision'] = revision + 1;
    next['updated_at'] = now.toUtc().toIso8601String();
    return CookingProfile.fromJson(next);
  }

  CookingProfile registerExplicit({
    required PreferenceScope scope,
    required String dimension,
    required int direction,
    required String declaration,
    required int expectedRevision,
    required DateTime now,
  }) {
    if (expectedRevision != revision) {
      throw StateError('Profileが更新されています。再読込してください。');
    }
    if (now.isBefore(DateTime.parse(_json['updated_at'] as String))) {
      throw ArgumentError('Profile time moved backwards.');
    }
    final next = toJson();
    final preferences = next['preferences'] as List;
    if (next['profile_schema_version'] == '1.0.0') {
      for (final p in preferences) {
        p['source_kind'] = 'feedback';
      }
    }
    preferences.removeWhere(
      (p) =>
          p['dimension'] == dimension &&
          p['scope']['kind'] == scope.kind.name &&
          p['scope']['value'] == scope.value,
    );
    preferences.add({
      'scope': scope.toJson(),
      'dimension': dimension,
      'direction': direction,
      'source_kind': 'explicit_user',
      'declaration': declaration.trim(),
      'confirmed_at': now.toUtc().toIso8601String(),
    });
    next['profile_schema_version'] = '1.1.0';
    next['revision'] = revision + 1;
    next['updated_at'] = now.toUtc().toIso8601String();
    return CookingProfile.fromJson(next);
  }
}
