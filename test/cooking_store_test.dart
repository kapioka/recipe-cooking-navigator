import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_cooking_navigator/data/cooking_store.dart';
import 'package:recipe_cooking_navigator/domain/recipe_document.dart';
import 'package:recipe_cooking_navigator/domain/recipe_validator.dart';
import 'package:recipe_cooking_navigator/domain/session_assessment.dart';

void main() {
  late RecipeValidator validator;
  late RecipeDocument recipe;

  setUpAll(() async {
    validator = RecipeValidator.fromSchemaString(
      await File('schemas/recipe-v2.schema.json').readAsString(),
    );
    recipe = validator.validateSource(
      await File('examples/recipe-example.json').readAsString(),
    );
  });

  test(
    'fixes snapshot/context at start, preserves it on move and completion',
    () async {
      final store = CookingStore(null, validator);
      final context = recipe.contextFor(3);
      await store.startCooking(recipe, context, 'step-onion');
      final started = await store.read();
      final initial = (started['progress'] as Map)[recipe.id] as Map;
      final startedAt = initial['started_at'];
      final savedContext = jsonEncode(initial['cooking_context']);

      await store.updatePosition(recipe.id, recipe.revision, 'step-pork');
      final moved = await store.read();
      final progress = (moved['progress'] as Map)[recipe.id] as Map;
      expect(progress['step_id'], 'step-pork');
      expect(progress['started_at'], startedAt);
      expect(jsonEncode(progress['cooking_context']), savedContext);

      await store.complete(recipe.id, recipe.revision);
      final completed = await store.read();
      expect(completed['progress'], isEmpty);
      final session = (completed['sessions'] as List).single as Map;
      expect(session['revision'], recipe.revision);
      expect(jsonEncode(session['cooking_context']), savedContext);
      expect(session['recipe_snapshot'], recipe.raw);
    },
  );

  test('persists v2 progress and first-use help state', () async {
    final directory = await Directory.systemTemp.createTemp(
      'cooking-store-test-',
    );
    addTearDown(() async => directory.delete(recursive: true));
    final file = File('${directory.path}/cooking-v2.json');
    final store = CookingStore(file, validator);
    await store.startCooking(recipe, recipe.contextFor(2), 'step-onion');
    await store.markHelpSeen();

    final reopened = await CookingStore(file, validator).read();
    expect(reopened['storage_version'], 2);
    expect(reopened['help_seen'], isTrue);
    expect((reopened['progress'] as Map)[recipe.id]['step_id'], 'step-onion');
    expect(await File('${file.path}.bak').exists(), isTrue);
  });

  test('reads a valid backup when the primary file is malformed', () async {
    final directory = await Directory.systemTemp.createTemp(
      'cooking-store-backup-test-',
    );
    addTearDown(() async => directory.delete(recursive: true));
    final file = File('${directory.path}/cooking-v2.json');
    final store = CookingStore(file, validator);
    await store.startCooking(recipe, recipe.contextFor(2), 'step-onion');
    await store.markHelpSeen();
    await file.writeAsString('{broken');

    final recovered = await CookingStore(file, validator).read();
    expect((recovered['progress'] as Map)[recipe.id]['step_id'], 'step-onion');
  });

  test('rejects invalid positions and malformed sessions', () async {
    final store = CookingStore(null, validator);
    await expectLater(
      store.startCooking(recipe, recipe.contextFor(2), ''),
      throwsFormatException,
    );
    await expectLater(
      store.updatePosition('', 1, 'step-onion'),
      throwsFormatException,
    );
    await expectLater(
      store.updatePosition(recipe.id, recipe.revision, 'missing'),
      throwsFormatException,
    );

    final directory = await Directory.systemTemp.createTemp(
      'cooking-store-invalid-test-',
    );
    addTearDown(() async => directory.delete(recursive: true));
    final file = File('${directory.path}/cooking-v2.json');
    await file.writeAsString(
      jsonEncode({
        'storage_version': 2,
        'help_seen': false,
        'progress': <String, dynamic>{},
        'sessions': [
          {'session_id': 'incomplete'},
        ],
      }),
    );
    await expectLater(
      CookingStore(file, validator).read(),
      throwsFormatException,
    );
  });

  test('rejects a modified resolved amount instead of falling back', () async {
    final directory = await Directory.systemTemp.createTemp(
      'cooking-store-context-test-',
    );
    addTearDown(() async => directory.delete(recursive: true));
    final file = File('${directory.path}/cooking-v2.json');
    final store = CookingStore(file, validator);
    await store.startCooking(recipe, recipe.contextFor(4), 'step-onion');
    final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final progress = (data['progress'] as Map)[recipe.id] as Map;
    final context = progress['cooking_context'] as Map;
    final amount = (context['resolved_amounts'] as List).first as Map;
    amount['quantity']['value']['numerator'] = '999';
    await file.writeAsString(jsonEncode(data));
    final backup = File('${file.path}.bak');
    if (await backup.exists()) await backup.delete();

    await expectLater(
      CookingStore(file, validator).read(),
      throwsFormatException,
    );
  });

  test(
    'adds an assessment to an existing session without migrating older data',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'assessment-test-',
      );
      addTearDown(() async => directory.delete(recursive: true));
      final file = File('${directory.path}/cooking-v2.json');
      final store = CookingStore(file, validator);
      await store.startCooking(recipe, recipe.contextFor(4), 'step-onion');
      await store.complete(recipe.id, recipe.revision);
      final before = await store.read();
      final original =
          (before['sessions'] as List).single as Map<String, dynamic>;
      expect(original.containsKey('assessment'), isFalse);

      const assessment = SessionAssessment(
        actualTimeMinutes: 25,
        difficultyScore: 3,
        difficultyComment: '火加減に注意した',
        issues: ['時間がかかった'],
        changesMade: [
          {'description': '醤油を減らした'},
        ],
        overall: 4,
        taste: [
          {'dimension': 'saltiness', 'deviation': -1, 'comment': ''},
        ],
        comment: '食べやすい',
        nextTimeIntent: ['もう少し塩味を足す'],
      );
      await store.saveAssessment(original['session_id'] as String, assessment);
      final reopened = await CookingStore(file, validator).read();
      final saved =
          (reopened['sessions'] as List).single as Map<String, dynamic>;
      expect(saved['assessment'], assessment.toJson());
      expect(saved['recipe_snapshot'], original['recipe_snapshot']);
      expect(saved['cooking_context'], original['cooking_context']);
      expect(saved['session_id'], original['session_id']);
      expect(reopened['storage_version'], 2);

      final persisted = await file.readAsString();
      await expectLater(
        store.saveAssessment('missing', assessment),
        throwsFormatException,
      );
      expect(await file.readAsString(), persisted);
    },
  );

  test(
    'rejects a corrupt assessment without overwriting the stored session',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'assessment-bad-',
      );
      addTearDown(() async => directory.delete(recursive: true));
      final file = File('${directory.path}/cooking-v2.json');
      final store = CookingStore(file, validator);
      await store.startCooking(recipe, recipe.contextFor(2), 'step-onion');
      await store.complete(recipe.id, recipe.revision);
      final valid = await file.readAsString();
      final changed = jsonDecode(valid) as Map<String, dynamic>;
      ((changed['sessions'] as List).single
          as Map<String, dynamic>)['assessment'] = {
        'actual_time_minutes': 0,
      };
      await file.writeAsString(jsonEncode(changed));
      final backup = File('${file.path}.bak');
      if (await backup.exists()) await backup.delete();
      await expectLater(
        CookingStore(file, validator).read(),
        throwsFormatException,
      );
      expect(await file.readAsString(), jsonEncode(changed));
    },
  );
}
