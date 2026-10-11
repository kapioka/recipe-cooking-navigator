import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_cooking_navigator/data/cooking_store.dart';
import 'package:recipe_cooking_navigator/domain/feedback_validator.dart';
import 'package:recipe_cooking_navigator/domain/feedback_document.dart';
import 'package:recipe_cooking_navigator/domain/recipe_validator.dart';
import 'package:recipe_cooking_navigator/domain/session_assessment.dart';

void main() {
  late FeedbackValidator validator;
  late String validSource;

  setUpAll(() async {
    validator = FeedbackValidator.fromSchemaStrings(
      feedbackSchemaSource: await File('schemas/feedback-v2.schema.json')
          .readAsString(),
      recipeSchemaSource: await File('schemas/recipe-v2.schema.json')
          .readAsString(),
    );
    validSource = await File('examples/feedback-example.json').readAsString();
  });

  test('validates the complete feedback example with local refs', () {
    expect(validator.validateSource(validSource)['schema_version'], '2.0.0');
  });

  test('rejects a modified saved cooking context', () {
    final document = jsonDecode(validSource) as Map<String, dynamic>;
    final session = document['cook_session'] as Map<String, dynamic>;
    final context = session['cooking_context'] as Map<String, dynamic>;
    final amount = (context['resolved_amounts'] as List).first as Map;
    amount['quantity']['value']['numerator'] = '201';
    expect(
      () => validator.validateDocument(document),
      throwsA(isA<FeedbackValidationException>()),
    );
  });

  test('rejects different recipe IDs and stale next revisions', () {
    final different = jsonDecode(validSource) as Map<String, dynamic>;
    final session = different['cook_session'] as Map<String, dynamic>;
    final snapshot = session['recipe_snapshot'] as Map<String, dynamic>;
    (snapshot['recipe'] as Map<String, dynamic>)['id'] = 'different';
    expect(
      () => validator.validateDocument(different),
      throwsA(isA<FeedbackValidationException>()),
    );

    final stale = jsonDecode(validSource) as Map<String, dynamic>;
    (stale['revision_request'] as Map<String, dynamic>)['next_revision'] = 1;
    expect(
      () => validator.validateDocument(stale),
      throwsA(isA<FeedbackValidationException>()),
    );
  });

  test(
    'extracts feedback source data from a persisted completed session',
    () async {
      final recipeValidator = RecipeValidator.fromSchemaString(
        await File('schemas/recipe-v2.schema.json').readAsString(),
      );
      final recipe = recipeValidator.validateSource(
        await File('examples/recipe-example.json').readAsString(),
      );
      final store = CookingStore(null, recipeValidator);
      await store.startCooking(recipe, recipe.contextFor(4), 'step-onion');
      await store.complete(recipe.id, recipe.revision);
      final session = ((await store.read())['sessions'] as List).single;

      final source = FeedbackCookingSource.fromStoredSession(
        Map<String, dynamic>.from(session as Map),
      );
      expect(source.recipeId, recipe.id);
      expect(source.recipeRevision, recipe.revision);
      expect(source.cookingContext.targetServings, 4);
      expect(source.recipeSnapshot, recipe.raw);
    },
  );

  test(
    'builds Feedback from a cooked revision and a different chosen revision',
    () async {
      final recipeValidator = RecipeValidator.fromSchemaString(
        await File('schemas/recipe-v2.schema.json').readAsString(),
      );
      final first = recipeValidator.validateSource(
        await File('examples/recipe-example.json').readAsString(),
      );
      final secondJson =
          jsonDecode(jsonEncode(first.raw)) as Map<String, dynamic>;
      final recipeData = secondJson['recipe'] as Map<String, dynamic>;
      recipeData['revision'] = first.revision + 1;
      recipeData['parent_revision'] = first.revision;
      final second = recipeValidator.validateDocument(secondJson);
      final store = CookingStore(null, recipeValidator);
      await store.startCooking(first, first.contextFor(4), 'step-onion');
      await store.complete(first.id, first.revision);
      final session =
          ((await store.read())['sessions'] as List).single
              as Map<String, dynamic>;
      await store.saveAssessment(
        session['session_id'] as String,
        const SessionAssessment(
          actualTimeMinutes: 30,
          difficultyScore: 2,
          difficultyComment: '',
          issues: [],
          changesMade: [
            {'description': '具材を小さくした'},
          ],
          overall: 4,
          taste: [
            {'dimension': 'saltiness', 'deviation': 1, 'comment': ''},
          ],
          comment: '次回は薄味',
          nextTimeIntent: ['塩味を下げる'],
        ),
      );
      final assessed =
          ((await store.read())['sessions'] as List).single
              as Map<String, dynamic>;
      final feedback = FeedbackDocumentBuilder(validator).build(
        completedSession: assessed,
        improvementRecipe: second,
        knownRevisions: [first, second],
        goal: '塩味を調整する',
        preserveSuccessfulParts: true,
      );
      expect((feedback['recipe_snapshot'] as Map)['recipe']['revision'], 2);
      final cooked = feedback['cook_session'] as Map<String, dynamic>;
      expect(cooked['recipe_revision'], 1);
      expect(cooked['recipe_snapshot'], first.raw);
      expect(cooked['cooking_context'], first.contextFor(4).toJson());
      expect(cooked['actual_time_minutes'], 30);
      expect((feedback['revision_request'] as Map)['next_revision'], 3);
      expect(validator.validateSource(jsonEncode(feedback)), feedback);
      expect((await store.read())['storage_version'], 2);

      expect(
        () => FeedbackDocumentBuilder(validator).build(
          completedSession: assessed,
          improvementRecipe: second,
          knownRevisions: [first],
          goal: '塩味を調整する',
          preserveSuccessfulParts: true,
        ),
        throwsFormatException,
      );
    },
  );
}
