import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_cooking_navigator/application/recipe_library_controller.dart';
import 'package:recipe_cooking_navigator/data/cooking_store.dart';
import 'package:recipe_cooking_navigator/data/recipe_document_store.dart';
import 'package:recipe_cooking_navigator/data/recipe_tag_store.dart';
import 'package:recipe_cooking_navigator/data/recipe_version_state_store.dart';
import 'package:recipe_cooking_navigator/domain/feedback_document.dart';
import 'package:recipe_cooking_navigator/domain/feedback_validator.dart';
import 'package:recipe_cooking_navigator/domain/recipe_validator.dart';
import 'package:recipe_cooking_navigator/domain/session_assessment.dart';

void main() {
  test(
    'Feedback revision returns without changing active or cooked data',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'recipe-roundtrip-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final recipeValidator = RecipeValidator.fromSchemaString(
        await File('schemas/recipe-v2.schema.json').readAsString(),
      );
      final feedbackValidator = FeedbackValidator.fromSchemaStrings(
        feedbackSchemaSource: await File('schemas/feedback-v2.schema.json')
            .readAsString(),
        recipeSchemaSource: await File('schemas/recipe-v2.schema.json')
            .readAsString(),
      );
      final documentStore = FileRecipeDocumentStore(
        File('${directory.path}/recipes.json'),
      );
      final tagStore = FileRecipeTagStore(File('${directory.path}/tags.json'));
      final versionStore = FileRecipeVersionStateStore(
        File('${directory.path}/versions.json'),
      );
      final cookingStore = CookingStore(
        File('${directory.path}/cooking.json'),
        recipeValidator,
      );
      RecipeLibraryController createController() => RecipeLibraryController(
        documentStore,
        tagStore,
        recipeValidator,
        () async => null,
        cookingStore: cookingStore,
        recipeVersionStateStore: versionStore,
      );

      final controller = createController();
      await controller.load();
      final firstSource = await File('examples/recipe-example.json')
          .readAsString();
      expect(
        (await controller.importSource(firstSource)).status,
        RecipeImportStatus.imported,
      );
      final first = recipeValidator.validateSource(firstSource);
      final secondJson =
          jsonDecode(jsonEncode(first.raw)) as Map<String, dynamic>;
      final secondRecipe = secondJson['recipe'] as Map<String, dynamic>;
      secondRecipe['revision'] = 2;
      secondRecipe['parent_revision'] = 1;
      secondRecipe['title'] = '調理した改良版';
      expect(
        (await controller.importSource(jsonEncode(secondJson))).status,
        RecipeImportStatus.imported,
      );
      final second = controller.revisionFor(first.id, 2)!;

      await cookingStore.startCooking(
        second,
        second.contextFor(2),
        'step-onion',
      );
      await cookingStore.complete(first.id, 2);
      final session =
          ((await cookingStore.read())['sessions'] as List).single
              as Map<String, dynamic>;
      await cookingStore.saveAssessment(
        session['session_id'] as String,
        const SessionAssessment(
          actualTimeMinutes: 25,
          difficultyScore: 2,
          difficultyComment: '',
          issues: [],
          changesMade: [],
          overall: 4,
          taste: [],
          comment: '前の版を基準に調整したい',
          nextTimeIntent: ['味を調整する'],
        ),
      );
      expect(
        (await controller.setActiveRevision(first.id, 1)).status,
        ActiveRevisionUpdateStatus.updated,
      );
      final assessedSession =
          ((await cookingStore.read())['sessions'] as List).single
              as Map<String, dynamic>;
      final feedback = FeedbackDocumentBuilder(feedbackValidator).build(
        completedSession: assessedSession,
        improvementRecipe: first,
        knownRevisions: controller.revisionsFor(first.id),
        goal: '良かった部分を残して調整する',
        preserveSuccessfulParts: true,
      );
      expect(feedbackValidator.validateSource(jsonEncode(feedback)), feedback);
      expect((feedback['recipe_snapshot'] as Map)['recipe']['revision'], 1);
      expect((feedback['cook_session'] as Map)['recipe_revision'], 2);
      expect((feedback['revision_request'] as Map)['next_revision'], 3);

      final thirdJson =
          jsonDecode(jsonEncode(first.raw)) as Map<String, dynamic>;
      final thirdRecipe = thirdJson['recipe'] as Map<String, dynamic>;
      thirdRecipe['revision'] = 3;
      thirdRecipe['parent_revision'] = 1;
      thirdRecipe['title'] = '以前の版から再調整';
      final thirdSource = jsonEncode(thirdJson);
      expect(
        (await controller.importSource(thirdSource)).status,
        RecipeImportStatus.imported,
      );
      expect(controller.latestRecipeFor(first.id)?.revision, 3);
      expect(controller.activeRecipeFor(first.id)?.revision, 1);
      expect(controller.revisionFor(first.id, 3)?.parentRevision, 1);
      expect(
        (await controller.importSource(thirdSource)).status,
        RecipeImportStatus.alreadyExists,
      );
      thirdRecipe['title'] = '同じVersionの異なる内容';
      expect(
        (await controller.importSource(jsonEncode(thirdJson))).status,
        RecipeImportStatus.failed,
      );

      final reopened = createController();
      await reopened.load();
      expect(reopened.revisionsFor(first.id).map((recipe) => recipe.revision), [
        3,
        2,
        1,
      ]);
      expect(reopened.latestRecipeFor(first.id)?.revision, 3);
      expect(reopened.activeRecipeFor(first.id)?.revision, 1);
      expect(reopened.revisionFor(first.id, 3)?.parentRevision, 1);
      final storedSession =
          ((await cookingStore.read())['sessions'] as List).single
              as Map<String, dynamic>;
      expect(storedSession['revision'], 2);
      expect(storedSession['assessment'], assessedSession['assessment']);
      expect((await documentStore.loadDocuments()), hasLength(3));

      final third = reopened.revisionFor(first.id, 3)!;
      await cookingStore.startCooking(third, third.contextFor(2), 'step-onion');
      await cookingStore.complete(first.id, 3);
      final secondSession = ((await cookingStore.read())['sessions'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((session) => session['revision'] == 3);
      await cookingStore.saveAssessment(
        secondSession['session_id'] as String,
        const SessionAssessment(
          actualTimeMinutes: 24,
          difficultyScore: 2,
          difficultyComment: '',
          issues: [],
          changesMade: [],
          overall: 5,
          taste: [],
          comment: 'この版をさらに調整する',
          nextTimeIntent: ['香りを調整する'],
        ),
      );
      final assessedSecondSession =
          ((await cookingStore.read())['sessions'] as List)
              .cast<Map<String, dynamic>>()
              .singleWhere((session) => session['revision'] == 3);
      final secondFeedback = FeedbackDocumentBuilder(feedbackValidator).build(
        completedSession: assessedSecondSession,
        improvementRecipe: third,
        knownRevisions: reopened.revisionsFor(first.id),
        goal: '良かった部分を残してさらに調整する',
        preserveSuccessfulParts: true,
      );
      expect(
        feedbackValidator.validateSource(jsonEncode(secondFeedback)),
        secondFeedback,
      );
      expect((secondFeedback['revision_request'] as Map)['next_revision'], 4);
      final fourthJson =
          jsonDecode(jsonEncode(third.raw)) as Map<String, dynamic>;
      final fourthRecipe = fourthJson['recipe'] as Map<String, dynamic>;
      fourthRecipe['revision'] = 4;
      fourthRecipe['parent_revision'] = 3;
      expect(
        (await reopened.importSource(jsonEncode(fourthJson))).status,
        RecipeImportStatus.imported,
      );
      final finalController = createController();
      await finalController.load();
      expect(finalController.latestRecipeFor(first.id)?.revision, 4);
      expect(finalController.activeRecipeFor(first.id)?.revision, 1);
      expect(finalController.revisionFor(first.id, 4)?.parentRevision, 3);
      expect((await documentStore.loadDocuments()), hasLength(4));
      expect(((await cookingStore.read())['sessions'] as List), hasLength(2));
    },
  );
}
