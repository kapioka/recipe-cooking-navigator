import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:json_schema/json_schema.dart';
import 'package:recipe_cooking_navigator/domain/cooking_profile.dart';
import 'package:recipe_cooking_navigator/domain/feedback_validator.dart';
import 'package:recipe_cooking_navigator/domain/preference_candidate.dart';
import 'package:recipe_cooking_navigator/domain/preference_evidence.dart';

void main() {
  late FeedbackValidator validator;
  late Map<String, dynamic> sample;
  final now = DateTime.utc(2026, 10, 3);
  const engine = PreferenceCandidateEngine();
  final category = PreferenceScope(PreferenceScopeKind.category, 'main');
  setUpAll(() {
    validator = FeedbackValidator.fromSchemaStrings(
      feedbackSchemaSource: File('schemas/feedback-v2.schema.json')
          .readAsStringSync(),
      recipeSchemaSource: File('schemas/recipe-v2.schema.json')
          .readAsStringSync(),
    );
    sample = jsonDecode(
      File('examples/feedback-example.json').readAsStringSync(),
    ) as Map<String, dynamic>;
  });

  PreferenceEvidence evidence(
    int n, {
    String? session,
    String? recipe,
    int deviation = 1,
    int? intent,
    Set<String> categories = const {'main'},
  }) {
    final feedback = jsonDecode(jsonEncode(sample)) as Map<String, dynamic>;
    final cook = feedback['cook_session'] as Map<String, dynamic>;
    cook['id'] = session ?? 'cook-$n';
    final recipeId = recipe ?? 'recipe-${n % 2}';
    cook['recipe_id'] = recipeId;
    (cook['recipe_snapshot'] as Map)['recipe']['id'] = recipeId;
    (feedback['recipe_snapshot'] as Map)['recipe']['id'] = recipeId;
    (feedback['evaluation'] as Map)['taste'] = [
      {'dimension': 'saltiness', 'deviation': deviation, 'comment': ''},
    ];
    return PreferenceEvidence.create(
      feedbackId: 'feedback-$n',
      createdAt: now,
      feedback: feedback,
      validator: validator,
      categories: categories,
      confirmedIntents: {'saltiness': ?intent},
    );
  }

  List<PreferenceEvidence> qualifying() => [
    evidence(1, intent: -1),
    evidence(2),
    evidence(3),
  ];

  test(
    'threshold, direction, immutable evidence, and order are deterministic',
    () {
      final rows = qualifying();
      final before = jsonEncode(rows.map((e) => e.toJson()).toList());
      expect(engine.propose(rows.take(2), scope: category), isEmpty);
      final candidate = engine.propose(rows, scope: category).single;
      expect(candidate.score, 4);
      expect(candidate.direction, -1);
      expect(candidate.status, PreferenceCandidateStatus.proposed);
      expect(
        engine.propose(rows.reversed, scope: category).single.toJson(),
        candidate.toJson(),
      );
      expect(jsonEncode(rows.map((e) => e.toJson()).toList()), before);
      expect(() => candidate.evidenceIds.add('bad'), throwsUnsupportedError);
      final copy = rows.first.toJson();
      copy['feedback_id'] = 'changed';
      expect(rows.first.id, 'feedback-1');
    },
  );

  test('duplicate identifiers and alternate feedback for one cook never add points', () {
    final rows = qualifying();
    expect(engine.propose([...rows, ...rows], scope: category).single.score, 4);
    expect(
      engine.propose([
        rows.first,
        evidence(9, session: 'cook-1', intent: -1),
        rows[1],
      ], scope: category),
      isEmpty,
    );
    expect(
      () => engine.propose([
        rows.first,
        evidence(1, deviation: -1),
      ], scope: category),
      throwsFormatException,
    );
    expect(
      () => engine.propose([
        rows.first,
        evidence(8, session: 'cook-1'),
      ], scope: category),
      throwsFormatException,
    );
  });

  test(
    'opposition subtracts and conflicting reports from same session abstain',
    () {
      expect(
        engine.propose([
          ...qualifying(),
          evidence(4, deviation: -1),
        ], scope: category),
        isEmpty,
      );
      expect(
        engine.propose([
          ...qualifying(),
          evidence(9, session: 'cook-1', deviation: -1),
        ], scope: category),
        isEmpty,
      );
      expect(
        engine.propose([
          ...qualifying(),
          evidence(9, session: 'cook-1', deviation: 0),
        ], scope: category),
        isEmpty,
      );
    },
  );

  test('free text and health constraints are never classified', () {
    final feedback = jsonDecode(jsonEncode(sample)) as Map<String, dynamic>;
    (feedback['evaluation'] as Map)['next_time_intent'] = [
      '塩を減らす',
      '医師に相談',
      'アレルギー',
    ];
    final row = PreferenceEvidence.create(
      feedbackId: 'text',
      createdAt: now,
      feedback: feedback,
      validator: validator,
    );
    expect(row.votes, {'saltiness': 0});
    expect(
      () => PreferenceEvidence.create(
        feedbackId: 'bad',
        createdAt: now,
        feedback: feedback,
        validator: validator,
        confirmedIntents: {'allergy': 1},
      ),
      throwsFormatException,
    );
  });

  test('global requires diverse supporting categories; scope never widens silently', () {
    final global = PreferenceScope(PreferenceScopeKind.global, '*');
    expect(engine.propose(qualifying(), scope: global), isEmpty);
    final rows = [
      evidence(1, intent: -1),
      evidence(2),
      evidence(3, categories: {'soup'}),
    ];
    expect(engine.propose(rows, scope: global), hasLength(1));
    expect(engine.propose(rows, scope: category), isEmpty);
    expect(
      engine.propose(
        qualifying(),
        scope: PreferenceScope(PreferenceScopeKind.recipe, 'recipe-1'),
      ),
      isEmpty,
    );
  });

  test(
    'rejection persists for same cooks, new repeated cook can propose again',
    () {
      final rows = qualifying();
      final proposal = engine.propose(rows, scope: category).single;
      final rejected = proposal.decide(PreferenceCandidateStatus.rejected);
      expect(
        engine.propose(rows, scope: category, previous: [rejected]),
        isEmpty,
      );
      expect(
        engine.propose(
          [...rows, evidence(9, session: 'cook-1')],
          scope: category,
          previous: [rejected],
        ),
        isEmpty,
      );
      expect(
        engine.propose(
          [...rows, evidence(4)],
          scope: category,
          previous: [rejected],
        ),
        hasLength(1),
      );
      expect(
        () => rejected.decide(PreferenceCandidateStatus.accepted),
        throwsStateError,
      );
    },
  );

  test(
    'only explicit acceptance changes Profile and stale revision fails closed',
    () {
      final profile = CookingProfile.create('profile-local', now);
      final candidate = engine.propose(qualifying(), scope: category).single;
      expect(profile.toJson()['preferences'], isEmpty);
      expect(
        () => profile.accept(candidate, expectedRevision: 0, now: now),
        throwsStateError,
      );
      final updated = profile.accept(candidate, expectedRevision: 1, now: now);
      expect(updated.revision, 2);
      expect(profile.revision, 1);
      expect(profile.toJson()['preferences'], isEmpty);
      expect(
        CookingProfile.fromJson(updated.toJson()).toJson(),
        updated.toJson(),
      );
      expect(updated.toJson()['explicit_constraints'], isEmpty);
      expect(
        () => updated.accept(
          candidate.decide(PreferenceCandidateStatus.rejected),
          expectedRevision: 2,
          now: now,
        ),
        throwsStateError,
      );
    },
  );

  test(
    'new documents conform to schemas with only local reference resolution',
    () {
      final schemas = <String, dynamic>{};
      for (final name in [
        'recipe-v2',
        'feedback-v2',
        'feedback-evidence-v1',
        'cooking-profile-v1',
        'cooking-profile-v1.1',
        'preference-candidates-v1',
      ]) {
        schemas['$name.schema.json'] = jsonDecode(
          File('schemas/$name.schema.json').readAsStringSync(),
        );
      }
      JsonSchema schema(String name) => JsonSchema.create(
        schemas['$name.schema.json'],
        schemaVersion: SchemaVersion.draft2020_12,
        refProvider: RefProvider.sync(
          (ref) => schemas[Uri.parse(ref).pathSegments.last],
        ),
      );
      final candidate = engine.propose(qualifying(), scope: category).single;
      final profile = CookingProfile.create(
        'local',
        now,
      ).accept(candidate, expectedRevision: 1, now: now);
      final documents = {
        'feedback-evidence-v1': qualifying().first.toJson(),
        'cooking-profile-v1': profile.toJson(),
        'cooking-profile-v1.1': profile
            .registerExplicit(
              scope: PreferenceScope(
                PreferenceScopeKind.recipe,
                'single-recipe',
              ),
              dimension: 'saltiness',
              direction: 1,
              declaration: '塩味が強めの料理が好き',
              expectedRevision: 2,
              now: now,
            )
            .toJson(),
        'preference-candidates-v1': {
          'candidate_schema_version': '1.0.0',
          'type': 'preference_candidates',
          'candidates': [candidate.toJson()],
        },
      };
      for (final entry in documents.entries) {
        final result = schema(entry.key).validate(entry.value);
        expect(result.isValid, isTrue, reason: result.errors.toString());
        final invalid = {...entry.value, 'unexpected': true};
        expect(schema(entry.key).validate(invalid).isValid, isFalse);
      }
      for (final entry in {
        'feedback-evidence-v1': 'feedback-evidence-example',
        'cooking-profile-v1': 'cooking-profile-example',
        'cooking-profile-v1.1': 'cooking-profile-explicit-example',
        'preference-candidates-v1': 'preference-candidates-example',
      }.entries) {
        final example = jsonDecode(
          File('examples/${entry.value}.json').readAsStringSync(),
        );
        final result = schema(entry.key).validate(example);
        expect(result.isValid, isTrue, reason: result.errors.toString());
      }
      final series =
          (jsonDecode(
                File('examples/preference-evidence-series-example.json')
                    .readAsStringSync(),
              ) as List)
              .map(
                (e) => PreferenceEvidence.fromJson(
                  e as Map<String, dynamic>,
                  validator,
                ),
              )
              .toList();
      final exampleCandidate = (jsonDecode(
        File('examples/preference-candidates-example.json').readAsStringSync(),
      ) as Map<String, dynamic>)['candidates'][0];
      expect(
        engine
            .propose(
              series,
              scope: PreferenceScope(PreferenceScopeKind.category, '主菜'),
            )
            .single
            .toJson(),
        exampleCandidate,
      );
    },
  );
}
