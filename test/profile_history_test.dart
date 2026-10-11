import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:json_schema/json_schema.dart';
import 'package:recipe_cooking_navigator/domain/cooking_profile.dart';
import 'package:recipe_cooking_navigator/domain/feedback_validator.dart';
import 'package:recipe_cooking_navigator/domain/preference_candidate.dart';
import 'package:recipe_cooking_navigator/domain/preference_evidence.dart';
import 'package:recipe_cooking_navigator/domain/preference_operation.dart';
import 'package:recipe_cooking_navigator/domain/profile_history.dart';

void main() {
  final validator = FeedbackValidator.fromSchemaStrings(
    feedbackSchemaSource: File('schemas/feedback-v2.schema.json')
        .readAsStringSync(),
    recipeSchemaSource: File('schemas/recipe-v2.schema.json')
        .readAsStringSync(),
  );
  final now = DateTime.utc(2026, 10, 4);
  final profile = CookingProfile.create('remote-profile', now);
  final root = ProfileHistoryRecord.bootstrap(
    profile,
    id: 'bootstrap',
    validator: validator,
  );
  PreferenceOperation explicit(String id, int revision, {int direction = -1}) =>
      PreferenceOperation.explicit(
        id: id,
        baseRevision: revision,
        now: now,
        scope: PreferenceScope(PreferenceScopeKind.global, '*'),
        dimension: 'saltiness',
        direction: direction,
        declaration: '普段の塩味の好み',
      );
  final next = ProfileHistoryRecord.update(
    root,
    explicit('operation-1', 1),
    validator: validator,
  );

  test(
    'unordered observations and identical retry reconstruct one immutable head',
    () {
      final end = ProfileHistoryRecord.update(
        next,
        explicit('operation-2', 2, direction: 1),
        validator: validator,
      );
      final history = ProfileHistory.validate([end, root, next, next]);
      expect(history.records.map((r) => r.id), [
        'bootstrap',
        'operation-1',
        'operation-2',
      ]);
      expect(history.head.result.revision, 3);
      expect(profile.toJson()['preferences'], isEmpty);
      final copy = history.head.toJson();
      copy['result_profile']['revision'] = 99;
      expect(history.head.result.revision, 3);
    },
  );

  test('branches, missing parents, alternate roots and duplicate ID conflicts stop', () {
    final competing = ProfileHistoryRecord.update(
      root,
      explicit('operation-other', 1, direction: 1),
      validator: validator,
    );
    final alternate = ProfileHistoryRecord.bootstrap(
      profile,
      id: 'different-bootstrap',
      validator: validator,
    );
    final duplicate = ProfileHistoryRecord.update(
      root,
      explicit('operation-1', 1, direction: 1),
      validator: validator,
    );
    for (final records in [
      [root, next, competing],
      [next],
      [root, alternate],
      [root, next, duplicate],
    ]) {
      expect(() => ProfileHistory.validate(records), throwsFormatException);
    }
    expect(competing.result.revision, 2); // Both records still exist.
  });

  test('digest changes, mismatched base and fabricated resulting state fail closed', () {
    var changed = next.toJson();
    changed['result_digest'] = '0' * 64;
    expect(
      () => ProfileHistoryRecord.fromJson(changed, validator),
      throwsFormatException,
    );
    changed = next.toJson();
    changed['result_profile']['preferences'][0]['direction'] = 1;
    changed['result_digest'] = profileDigest(
      CookingProfile.fromJson(changed['result_profile']),
    );
    final fabricated = ProfileHistoryRecord.fromJson(changed, validator);
    expect(
      () => ProfileHistory.validate([root, fabricated]),
      throwsFormatException,
    );
    changed = next.toJson();
    changed['base_profile']['explicit_constraints'] = ['altered'];
    changed['base_digest'] = profileDigest(
      CookingProfile.fromJson(changed['base_profile']),
    );
    final wrongBase = ProfileHistoryRecord.fromJson(changed, validator);
    expect(
      () => ProfileHistory.validate([root, wrongBase]),
      throwsFormatException,
    );
  });

  test('candidate approval is replayed from unchanged embedded Evidence', () {
    final rows =
        (jsonDecode(
              File('examples/preference-evidence-series-example.json')
                  .readAsStringSync(),
            ) as List)
            .map(
              (r) => PreferenceEvidence.fromJson(
                r as Map<String, dynamic>,
                validator,
              ),
            )
            .toList();
    final candidate = const PreferenceCandidateEngine()
        .propose(
          rows,
          scope: PreferenceScope(PreferenceScopeKind.category, '主菜'),
        )
        .single;
    final time = DateTime.utc(2026, 10, 5);
    final operation = PreferenceOperation.candidate(
      candidate.decide(PreferenceCandidateStatus.accepted),
      id: 'approved',
      baseRevision: 1,
      now: time,
    );
    final record = ProfileHistoryRecord.update(
      root,
      operation,
      evidence: rows,
      validator: validator,
    );
    expect(ProfileHistory.validate([record, root]).head.result.revision, 2);
    final child = ProfileHistoryRecord.update(
      record,
      PreferenceOperation.explicit(
        id: 'child',
        baseRevision: 2,
        now: time,
        scope: PreferenceScope(PreferenceScopeKind.global, '*'),
        dimension: 'aroma',
        direction: 1,
        declaration: '香りの好み',
      ),
      validator: validator,
    );
    final edited = record.toJson();
    edited['evidence'][0]['feedback']['evaluation']['comment'] = '過去の説明だけを変更';
    final changedAncestor = ProfileHistoryRecord.fromJson(edited, validator);
    expect(
      () => ProfileHistory.validate([root, changedAncestor, child]),
      throwsFormatException,
    );
    final missing = record.toJson();
    (missing['evidence'] as List).removeLast();
    expect(
      () => ProfileHistoryRecord.fromJson(missing, validator),
      throwsFormatException,
    );
    final rejected = PreferenceOperation.candidate(
      candidate.decide(PreferenceCandidateStatus.rejected),
      id: 'rejected',
      baseRevision: 1,
      now: time,
    );
    expect(
      () => ProfileHistoryRecord.update(
        root,
        rejected,
        evidence: rows,
        validator: validator,
      ),
      throwsFormatException,
    );
  });

  test(
    'new schemas resolve locally and reject extra or unapproved content',
    () {
      final sources = {
        for (final file in Directory('schemas').listSync().whereType<File>())
          file.uri.pathSegments.last: jsonDecode(file.readAsStringSync()),
      };
      JsonSchema schema(String name) => JsonSchema.create(
        sources['$name.schema.json'],
        schemaVersion: SchemaVersion.draft2020_12,
        refProvider: RefProvider.sync(
          (ref) => sources[Uri.parse(ref).pathSegments.last],
        ),
      );
      for (final record in [root, next]) {
        final result = schema('profile-history-v1').validate(record.toJson());
        expect(result.isValid, isTrue, reason: result.errors.toString());
        expect(
          schema('profile-history-v1')
              .validate({...record.toJson(), 'extra': true})
              .isValid,
          isFalse,
        );
      }
      expect(
        schema('preference-operation-v1')
            .validate(next.operation!.toJson())
            .isValid,
        isTrue,
      );
      final example = jsonDecode(
        File('examples/profile-history-explicit-example.json')
            .readAsStringSync(),
      ) as List;
      final history = ProfileHistory.validate(
        example.map(
          (e) => ProfileHistoryRecord.fromJson(
            e as Map<String, dynamic>,
            validator,
          ),
        ),
      );
      expect(history.head.result.revision, 2);
      for (final record in example) {
        final result = schema('profile-history-v1').validate(record);
        expect(result.isValid, isTrue, reason: result.errors.toString());
      }
    },
  );
}
