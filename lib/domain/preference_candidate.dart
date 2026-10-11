import 'preference_evidence.dart';
import 'session_assessment.dart';

enum PreferenceScopeKind { recipe, category, global }

enum PreferenceCandidateStatus { proposed, accepted, rejected }

class PreferenceScope {
  PreferenceScope(this.kind, this.value) {
    if ((kind == PreferenceScopeKind.global && value != '*') ||
        value.trim().isEmpty) {
      throw ArgumentError('Invalid preference scope.');
    }
  }
  final PreferenceScopeKind kind;
  final String value;
  Map<String, dynamic> toJson() => {'kind': kind.name, 'value': value};
}

class PreferenceCandidate {
  factory PreferenceCandidate.fromJson(Map<String, dynamic> json) {
    const keys = {
      'rules_version',
      'scope',
      'dimension',
      'direction',
      'score',
      'feedback_ids',
      'session_ids',
      'recipe_ids',
      'categories',
      'status',
    };
    if (json.length != keys.length ||
        json.keys.toSet().difference(keys).isNotEmpty ||
        json['rules_version'] != rulesVersion ||
        json['scope'] is! Map<String, dynamic> ||
        !SessionAssessment.tasteDimensions.contains(json['dimension']) ||
        json['direction'] is! int ||
        !{-1, 1}.contains(json['direction']) ||
        json['score'] is! int ||
        (json['score'] as int) < 4 ||
        !PreferenceCandidateStatus.values
            .map((e) => e.name)
            .contains(json['status'])) {
      throw const FormatException('Preference候補の形式が正しくありません。');
    }
    final rawScope = json['scope'] as Map<String, dynamic>;
    if (rawScope.length != 2 ||
        rawScope['value'] is! String ||
        !PreferenceScopeKind.values
            .map((e) => e.name)
            .contains(rawScope['kind'])) {
      throw const FormatException('Preference候補の適用範囲が不正です。');
    }
    List<String> ids(String key, int minimum) {
      final value = json[key];
      if (value is! List ||
          value.length < minimum ||
          value.any((e) => e is! String || e.trim().isEmpty) ||
          value.toSet().length != value.length) {
        throw const FormatException('Preference候補の根拠が不正です。');
      }
      return List.unmodifiable(value.cast<String>().toList()..sort());
    }

    final scope = PreferenceScope(
      PreferenceScopeKind.values.byName(rawScope['kind'] as String),
      rawScope['value'] as String,
    );
    return PreferenceCandidate._(
      scope: scope,
      dimension: json['dimension'] as String,
      direction: json['direction'] as int,
      score: json['score'] as int,
      evidenceIds: ids('feedback_ids', 3),
      sessionIds: ids('session_ids', 3),
      recipeIds: ids('recipe_ids', 2),
      categories: ids(
        'categories',
        scope.kind == PreferenceScopeKind.global ? 2 : 0,
      ),
      status: PreferenceCandidateStatus.values.byName(json['status'] as String),
    );
  }
  PreferenceCandidate._({
    required this.scope,
    required this.dimension,
    required this.direction,
    required this.score,
    required this.evidenceIds,
    required this.sessionIds,
    required this.recipeIds,
    required this.categories,
    this.status = PreferenceCandidateStatus.proposed,
  });

  static const rulesVersion = '1.0.0';
  final PreferenceScope scope;
  final String dimension;
  final int direction;
  final int score;
  final List<String> evidenceIds;
  final List<String> sessionIds;
  final List<String> recipeIds;
  final List<String> categories;
  final PreferenceCandidateStatus status;

  String get key =>
      canonicalPreferenceJson([scope.toJson(), dimension, direction]);
  String get evidenceKey =>
      canonicalPreferenceJson([rulesVersion, key, evidenceIds]);

  PreferenceCandidate decide(PreferenceCandidateStatus decision) {
    if (status != PreferenceCandidateStatus.proposed ||
        decision == PreferenceCandidateStatus.proposed) {
      throw StateError(
        'Only a proposed candidate can be accepted or rejected.',
      );
    }
    return PreferenceCandidate._(
      scope: scope,
      dimension: dimension,
      direction: direction,
      score: score,
      evidenceIds: evidenceIds,
      sessionIds: sessionIds,
      recipeIds: recipeIds,
      categories: categories,
      status: decision,
    );
  }

  Map<String, dynamic> toJson() => {
    'rules_version': rulesVersion,
    'scope': scope.toJson(),
    'dimension': dimension,
    'direction': direction,
    'score': score,
    'feedback_ids': evidenceIds,
    'session_ids': sessionIds,
    'recipe_ids': recipeIds,
    'categories': categories,
    'status': status.name,
  };
}

/// A pure, deterministic reducer. Never writes a Profile or changes evidence.
class PreferenceCandidateEngine {
  const PreferenceCandidateEngine();

  List<PreferenceCandidate> propose(
    Iterable<PreferenceEvidence> input, {
    required PreferenceScope scope,
    Iterable<PreferenceCandidate> previous = const [],
  }) {
    final all = <String, PreferenceEvidence>{};
    final sessionRecipes = <String, String>{};
    for (final evidence in input) {
      final old = all[evidence.id];
      if (old != null &&
          canonicalPreferenceJson(old.toJson()) !=
              canonicalPreferenceJson(evidence.toJson())) {
        throw const FormatException('同じFeedback IDの内容が競合しています。');
      }
      final recipe = sessionRecipes[evidence.sessionId];
      if (recipe != null && recipe != evidence.recipeId) {
        throw const FormatException('同じ調理記録が異なるRecipeを参照しています。');
      }
      sessionRecipes[evidence.sessionId] = evidence.recipeId;
      all[evidence.id] = evidence;
    }
    final eligible =
        all.values
            .where(
              (e) => switch (scope.kind) {
                PreferenceScopeKind.recipe => e.recipeId == scope.value,
                PreferenceScopeKind.category => e.categories.contains(
                  scope.value,
                ),
                PreferenceScopeKind.global => e.categories.isNotEmpty,
              },
            )
            .toList()
          ..sort((a, b) => a.id.compareTo(b.id));
    final dimensions = eligible.expand((e) => e.votes.keys).toSet().toList()
      ..sort();
    final result = <PreferenceCandidate>[];
    for (final dimension in dimensions) {
      final bySession = <String, List<PreferenceEvidence>>{};
      for (final e in eligible.where((e) => e.votes.containsKey(dimension))) {
        bySession.putIfAbsent(e.sessionId, () => []).add(e);
      }
      final votes = <String, int>{};
      for (final entry in bySession.entries) {
        final values = entry.value.map((e) => e.votes[dimension]!).toList();
        // Conflicting reports from one cook are ambiguous, never additive.
        if (values.map((v) => v.sign).toSet().length != 1) continue;
        values.sort((a, b) => b.abs().compareTo(a.abs()));
        votes[entry.key] = values.first;
      }
      final score = votes.values.fold(0, (a, b) => a + b);
      if (score.abs() < 4) continue;
      final supporting = votes.entries
          .where((v) => v.value.sign == score.sign)
          .map((v) => v.key)
          .toSet();
      final supporters = eligible
          .where(
            (e) =>
                supporting.contains(e.sessionId) &&
                e.votes.containsKey(dimension),
          )
          .toList();
      final recipes = supporters.map((e) => e.recipeId).toSet();
      final categories = supporters.expand((e) => e.categories).toSet();
      if (supporting.length < 3 ||
          recipes.length < 2 ||
          (scope.kind == PreferenceScopeKind.global && categories.length < 2)) {
        continue;
      }
      List<String> frozen(Iterable<String> values) =>
          List.unmodifiable(values.toSet().toList()..sort());
      final candidate = PreferenceCandidate._(
        scope: scope,
        dimension: dimension,
        direction: score.sign,
        score: score.abs(),
        evidenceIds: frozen(
          eligible
              .where(
                (e) =>
                    votes.containsKey(e.sessionId) &&
                    e.votes.containsKey(dimension),
              )
              .map((e) => e.id),
        ),
        sessionIds: frozen(supporting),
        recipeIds: frozen(recipes),
        categories: frozen(categories),
      );
      // A new identifier for the same cook does not defeat a rejection.
      final suppressed = previous.any(
        (old) =>
            old.key == candidate.key &&
            old.status != PreferenceCandidateStatus.proposed &&
            candidate.sessionIds.every(old.sessionIds.contains),
      );
      if (!suppressed) result.add(candidate);
    }
    return List.unmodifiable(result);
  }
}
