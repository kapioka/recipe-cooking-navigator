import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_cooking_navigator/data/preference_store.dart';
import 'package:recipe_cooking_navigator/domain/feedback_validator.dart';
import 'package:recipe_cooking_navigator/domain/preference_candidate.dart';
import 'package:recipe_cooking_navigator/domain/preference_evidence.dart';

void main() {
  late Directory directory;
  late File file;
  late PreferenceStore store;
  late FeedbackValidator validator;
  final now = DateTime.utc(2026, 10, 4);
  final scope = PreferenceScope(PreferenceScopeKind.category, 'main');
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('preference-store-');
    file = File('${directory.path}/preferences.json');
    validator = FeedbackValidator.fromSchemaStrings(
      feedbackSchemaSource: File('schemas/feedback-v2.schema.json')
          .readAsStringSync(),
      recipeSchemaSource: File('schemas/recipe-v2.schema.json')
          .readAsStringSync(),
    );
    store = PreferenceStore(file, validator);
  });
  tearDown(() => directory.delete(recursive: true));

  PreferenceEvidence row(int n, {int deviation = 1}) {
    final document = jsonDecode(
      File('examples/feedback-example.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final recipe = 'recipe-${n % 2}';
    document['cook_session']['id'] = 'session-$n';
    document['cook_session']['recipe_id'] = recipe;
    document['cook_session']['recipe_snapshot']['recipe']['id'] = recipe;
    document['recipe_snapshot']['recipe']['id'] = recipe;
    document['evaluation']['taste'] = [
      {'dimension': 'saltiness', 'deviation': deviation, 'comment': ''},
    ];
    return PreferenceEvidence.create(
      feedbackId: 'feedback-$n',
      createdAt: now,
      feedback: document,
      validator: validator,
      categories: {'main'},
      confirmedIntents: n == 1 ? {'saltiness': -1} : {},
    );
  }

  Future<PreferenceCandidate> proposal() async {
    await store.initialize('profile-local', now);
    for (var n = 1; n <= 3; n++) {
      await store.append(row(n));
    }
    return const PreferenceCandidateEngine()
        .propose((await store.load()).evidence, scope: scope)
        .single;
  }

  test(
    'append is idempotent, conflicting ID cannot overwrite original',
    () async {
      await store.append(row(1));
      final before = await file.readAsString();
      await store.append(row(1));
      expect(await file.readAsString(), before);
      await expectLater(store.append(row(1, deviation: -1)), throwsStateError);
      expect(await file.readAsString(), before);
      expect((await store.load()).evidence.single.toJson(), row(1).toJson());
    },
  );

  test(
    'instances sharing a path serialize concurrent appends and survive reload',
    () async {
      final other = PreferenceStore(
        File('${directory.path}/preferences.json'),
        validator,
      );
      await Future.wait([
        store.append(row(1)),
        other.append(row(2)),
        store.append(row(3)),
      ]);
      final reloaded = await other.load();
      expect(reloaded.evidence.map((e) => e.id).toSet(), {
        'feedback-1',
        'feedback-2',
        'feedback-3',
      });
      expect(reloaded.profile, isNull);
    },
  );

  test(
    'acceptance persists old Profile and rejects competing stale acceptance',
    () async {
      final candidate = await proposal();
      final before = await store.load();
      await store.decide(
        candidate,
        accept: true,
        expectedRevision: 1,
        now: now,
      );
      final reloaded = await PreferenceStore(file, validator).load();
      expect(reloaded.history.map((p) => p.revision), [1, 2]);
      expect(reloaded.history.first.toJson(), before.profile!.toJson());
      expect(reloaded.profile!.toJson()['preferences'], hasLength(1));
      expect(
        reloaded.decisions.single.status,
        PreferenceCandidateStatus.accepted,
      );
      final bytes = await file.readAsString();
      await expectLater(
        store.decide(candidate, accept: true, expectedRevision: 1, now: now),
        throwsStateError,
      );
      expect(await file.readAsString(), bytes);
    },
  );

  test('rejection persists without changing Profile and same evidence stays suppressed', () async {
    final candidate = await proposal();
    await store.decide(candidate, accept: false, expectedRevision: 1, now: now);
    final snapshot = await store.load();
    expect(snapshot.profile!.revision, 1);
    expect(snapshot.profile!.toJson()['preferences'], isEmpty);
    expect(
      const PreferenceCandidateEngine().propose(
        snapshot.evidence,
        scope: scope,
        previous: snapshot.decisions,
      ),
      isEmpty,
    );
    await expectLater(
      store.decide(candidate, accept: true, expectedRevision: 1, now: now),
      throwsStateError,
    );
  });

  test('changed evidence invalidates an already displayed candidate', () async {
    final candidate = await proposal();
    await store.append(row(4, deviation: -1));
    final before = await file.readAsString();
    await expectLater(
      store.decide(candidate, accept: true, expectedRevision: 1, now: now),
      throwsStateError,
    );
    expect(await file.readAsString(), before);
  });

  test('corrupt primary is not replaced with backup or empty data', () async {
    await store.append(row(1));
    await store.append(row(2));
    await file.writeAsString('{broken');
    final backup = await File('${file.path}.bak').readAsString();
    await expectLater(store.load(), throwsFormatException);
    await expectLater(store.append(row(3)), throwsFormatException);
    expect(await file.readAsString(), '{broken');
    expect(await File('${file.path}.bak').readAsString(), backup);
  });

  test('interrupted rename recovers valid backup, uncommitted temporary is not adopted', () async {
    await store.append(row(1));
    await file.rename('${file.path}.bak');
    expect((await store.load()).evidence.single.id, 'feedback-1');
    await store.append(row(2));
    expect((await store.load()).evidence, hasLength(2));
    await file.delete();
    await File('${file.path}.bak').delete();
    await File('${file.path}.tmp').writeAsString('{}');
    await expectLater(store.initialize('new', now), throwsFormatException);
    expect(await file.exists(), isFalse);
  });

  test('record returns stable ID for identical document and keeps changed evidence', () async {
    final document = row(1).feedback;
    final first = await store.record(
      feedback: document,
      categories: {'main'},
      confirmedIntents: {},
      now: now,
    );
    final second = await store.record(
      feedback: document,
      categories: {'main'},
      confirmedIntents: {},
      now: now.add(const Duration(days: 1)),
    );
    expect(second.id, first.id);
    expect((await store.load()).evidence, hasLength(1));
    final third = await store.record(
      feedback: document,
      categories: {'main'},
      confirmedIntents: {'saltiness': -1},
      now: now,
    );
    expect(third.id, isNot(first.id));
    expect((await store.load()).evidence, hasLength(2));
  });

  test(
    'unknown version, missing evidence and broken history fail closed',
    () async {
      final candidate = await proposal();
      await store.decide(
        candidate,
        accept: true,
        expectedRevision: 1,
        now: now,
      );
      final valid = await file.readAsString();
      for (final mutation in <void Function(Map<String, dynamic>)>[
        (data) => data['storage_version'] = 99,
        (data) => (data['evidence'] as List).clear(),
        (data) => data['profile_history'][1]['revision'] = 3,
        (data) => data['operations'][0]['candidate']['score'] = 99,
        (data) => data['profile_history'][1]['preferences'][0]['direction'] = 1,
      ]) {
        final data = jsonDecode(valid) as Map<String, dynamic>;
        mutation(data);
        await file.writeAsString(jsonEncode(data));
        await expectLater(store.load(), throwsFormatException);
      }
    },
  );

  Future<void> explicit(int revision, {PreferenceScope? target}) =>
      store.registerExplicit(
        scope: target ?? scope,
        dimension: 'saltiness',
        direction: 1,
        declaration: '塩味が強めの料理が好き',
        expectedRevision: revision,
        now: now,
      );

  test('explicit declaration needs no fabricated Feedback and rejects stale updates', () async {
    await store.initialize('profile-local', now);
    await explicit(
      1,
      target: PreferenceScope(PreferenceScopeKind.recipe, 'one-recipe'),
    );
    final snapshot = await PreferenceStore(file, validator).load();
    expect(snapshot.evidence, isEmpty);
    expect(snapshot.decisions, isEmpty);
    expect(snapshot.operations, hasLength(1));
    expect(snapshot.history.first.toJson()['profile_schema_version'], '1.0.0');
    expect(snapshot.profile!.toJson()['profile_schema_version'], '1.1.0');
    final value = (snapshot.profile!.toJson()['preferences'] as List).single;
    expect(value['source_kind'], 'explicit_user');
    expect(value.containsKey('feedback_ids'), isFalse);
    final before = await file.readAsString();
    await expectLater(explicit(1), throwsStateError);
    expect(await file.readAsString(), before);
  });

  test('candidate, explicit override, rejection and new acceptance replay in order', () async {
    final candidate = await proposal();
    await store.decide(candidate, accept: true, expectedRevision: 1, now: now);
    await explicit(2);
    await store.append(row(4));
    var snapshot = await store.load();
    final next = const PreferenceCandidateEngine()
        .propose(snapshot.evidence, scope: scope, previous: snapshot.decisions)
        .single;
    await store.decide(next, accept: false, expectedRevision: 3, now: now);
    await store.append(row(5));
    snapshot = await store.load();
    final third = const PreferenceCandidateEngine()
        .propose(snapshot.evidence, scope: scope, previous: snapshot.decisions)
        .single;
    await store.decide(third, accept: true, expectedRevision: 3, now: now);
    snapshot = await PreferenceStore(file, validator).load();
    expect(snapshot.history.map((p) => p.revision), [1, 2, 3, 4]);
    expect(snapshot.operations.map((o) => o.baseRevision), [1, 2, 3, 3]);
    expect(snapshot.decisions, hasLength(3));
    expect(
      snapshot.history[2].toJson()['preferences'][0]['source_kind'],
      'explicit_user',
    );
    expect(
      snapshot.profile!.toJson()['preferences'][0]['source_kind'],
      'feedback',
    );
  });

  test('legacy decisions migrate without rewriting snapshots or inventing rejection time', () async {
    final candidate = await proposal();
    await store.decide(candidate, accept: true, expectedRevision: 1, now: now);
    await store.append(row(4));
    var snapshot = await store.load();
    final next = const PreferenceCandidateEngine()
        .propose(snapshot.evidence, scope: scope, previous: snapshot.decisions)
        .single;
    await store.decide(next, accept: false, expectedRevision: 2, now: now);
    snapshot = await store.load();
    final legacy = jsonEncode({
      'storage_version': 1,
      'evidence': snapshot.evidence.map((e) => e.toJson()).toList(),
      'profile_history': snapshot.history.map((p) => p.toJson()).toList(),
      'decisions': snapshot.decisions.map((d) => d.toJson()).toList(),
    });
    await file.writeAsString(legacy);
    final loaded = await store.load();
    expect(await file.readAsString(), legacy);
    expect(loaded.operations.last.toJson()['decided_at'], isNull);
    await explicit(2);
    expect(await File('${file.path}.legacy-v1').readAsString(), legacy);
    expect(jsonDecode(await file.readAsString())['storage_version'], 2);
    final migrated = await store.load();
    expect(
      migrated.history.take(2).map((p) => p.toJson()),
      snapshot.history.map((p) => p.toJson()),
    );
    expect(
      migrated.operations.take(2).map((o) => o.id),
      loaded.operations.map((o) => o.id),
    );
    expect(migrated.operations[1].toJson()['decided_at'], isNull);
  });

  test(
    'migration refuses to overwrite a different retained legacy original',
    () async {
      await store.initialize('profile-local', now);
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      data['storage_version'] = 1;
      data.remove('operations');
      data['decisions'] = [];
      final legacy = jsonEncode(data);
      await file.writeAsString(legacy);
      await File('${file.path}.legacy-v1').writeAsString('other original');
      await expectLater(explicit(1), throwsStateError);
      expect(await file.readAsString(), legacy);
      expect(
        await File('${file.path}.legacy-v1').readAsString(),
        'other original',
      );
    },
  );

  test('explicit history deletion, duplication, altered value or base fails closed', () async {
    await store.initialize('profile-local', now);
    await explicit(1);
    final valid = await file.readAsString();
    for (final mutation in <void Function(Map<String, dynamic>)>[
      (d) => d['operations'].clear(),
      (d) => d['operations'].add(d['operations'][0]),
      (d) => d['operations'][0]['direction'] = -1,
      (d) => d['operations'][0]['base_revision'] = 99,
      (d) => d['operations'][0]['decided_at'] = null,
      (d) => d['profile_history'][1]['preferences'][0]['declaration'] = '改変',
    ]) {
      final data = jsonDecode(valid) as Map<String, dynamic>;
      mutation(data);
      await file.writeAsString(jsonEncode(data));
      await expectLater(store.load(), throwsFormatException);
    }
  });
}
