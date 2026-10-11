import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_cooking_navigator/application/recipe_library_controller.dart';
import 'package:recipe_cooking_navigator/data/cooking_store.dart';
import 'package:recipe_cooking_navigator/data/preparation_checklist_store.dart';
import 'package:recipe_cooking_navigator/data/recipe_archive_store.dart';
import 'package:recipe_cooking_navigator/data/recipe_document_store.dart';
import 'package:recipe_cooking_navigator/data/recipe_tag_store.dart';
import 'package:recipe_cooking_navigator/data/recipe_version_state_store.dart';
import 'package:recipe_cooking_navigator/domain/recipe_validator.dart';
import 'package:recipe_cooking_navigator/domain/session_assessment.dart';

void main() {
  late Directory directory;
  late RecipeValidator validator;
  late Map<String, dynamic> first;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('recipe-archive-test-');
    validator = RecipeValidator.fromSchemaString(
      await File('schemas/recipe-v2.schema.json').readAsString(),
    );
    first = jsonDecode(
      await File('examples/recipe-example.json').readAsString(),
    ) as Map<String, dynamic>;
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test(
    'archive and restore preserve revisions, active choice and cooking data',
    () async {
      final second = jsonDecode(jsonEncode(first)) as Map<String, dynamic>;
      (second['recipe'] as Map<String, dynamic>)
        ..['revision'] = 2
        ..['parent_revision'] = 1;
      final id = (first['recipe'] as Map<String, dynamic>)['id'] as String;
      final documents = FileRecipeDocumentStore(
        File('${directory.path}/recipes.json'),
      );
      final tags = FileRecipeTagStore(File('${directory.path}/tags.json'));
      final versions = FileRecipeVersionStateStore(
        File('${directory.path}/versions.json'),
      );
      final archive = RecipeArchiveStore(
        File('${directory.path}/archive.json'),
      );
      final cooking = CookingStore(
        File('${directory.path}/cooking.json'),
        validator,
      );
      final preparation = PreparationChecklistStore(
        File('${directory.path}/preparation.json'),
      );
      await documents.saveDocument(first);
      await documents.saveDocument(second);
      await versions.saveActiveRevision(id, 1);
      await tags.saveTags(id, ['平日']);
      await preparation.setChecked(id, 1, 'task-1', true);
      final recipe = validator.validateDocument(first);
      await cooking.startCooking(recipe, recipe.contextFor(2), 'step-onion');
      await cooking.complete(id, 1);

      RecipeLibraryController open() => RecipeLibraryController(
        documents,
        tags,
        validator,
        () async => null,
        cookingStore: cooking,
        preparationStore: preparation,
        recipeVersionStateStore: versions,
        archiveStore: archive,
      );

      final controller = open();
      await controller.load();
      expect(controller.recipes.single.revision, 1);
      expect(await controller.setArchived(id, true), contains('アーカイブ'));
      expect(controller.recipes, isEmpty);
      expect(controller.archivedRecipes.single.revision, 1);
      expect(await documents.loadDocuments(), hasLength(2));

      final reopened = open();
      await reopened.load();
      expect(reopened.recipes, isEmpty);
      expect(reopened.archivedRecipes.single.revision, 1);
      expect(reopened.latestRecipeFor(id)?.revision, 2);
      final third = jsonDecode(jsonEncode(first)) as Map<String, dynamic>;
      (third['recipe'] as Map<String, dynamic>)
        ..['revision'] = 3
        ..['parent_revision'] = 1;
      await reopened.importSource(jsonEncode(third));
      expect(reopened.archivedRecipes.single.revision, 1);
      expect(reopened.latestRecipeFor(id)?.revision, 3);
      expect(reopened.recipes, isEmpty);
      expect(reopened.tagsFor(id), ['平日']);
      expect((await cooking.read())['sessions'], hasLength(1));
      expect(await reopened.setArchived(id, false), contains('戻しました'));
      expect(reopened.recipes.single.revision, 1);
      expect(await preparation.checked(id, 1), {'task-1'});
    },
  );

  test(
    'complete delete removes only the archived recipe and related data',
    () async {
      final id = (first['recipe'] as Map<String, dynamic>)['id'] as String;
      final second = jsonDecode(jsonEncode(first)) as Map<String, dynamic>;
      (second['recipe'] as Map<String, dynamic>)
        ..['revision'] = 2
        ..['parent_revision'] = 1;
      final other = jsonDecode(jsonEncode(first)) as Map<String, dynamic>;
      (other['recipe'] as Map<String, dynamic>)['id'] = 'another-recipe-001';
      final documents = FileRecipeDocumentStore(
        File('${directory.path}/recipes.json'),
      );
      final tags = FileRecipeTagStore(File('${directory.path}/tags.json'));
      final versions = FileRecipeVersionStateStore(
        File('${directory.path}/versions.json'),
      );
      final archive = RecipeArchiveStore(
        File('${directory.path}/archive.json'),
      );
      final cooking = CookingStore(
        File('${directory.path}/cooking.json'),
        validator,
      );
      final preparation = PreparationChecklistStore(
        File('${directory.path}/preparation.json'),
      );
      for (final document in [first, second, other]) {
        await documents.saveDocument(document);
      }
      await versions.saveActiveRevision(id, 1);
      await tags.saveTags(id, ['平日']);
      await tags.saveTags('another-recipe-001', ['休日']);
      await preparation.setChecked(id, 1, 'task-1', true);
      final recipe = validator.validateDocument(first);
      await cooking.startCooking(recipe, recipe.contextFor(2), 'step-onion');
      await cooking.complete(id, 1);
      final session =
          ((await cooking.read())['sessions'] as List).single as Map;
      await cooking.saveAssessment(
        session['session_id'] as String,
        const SessionAssessment(
          actualTimeMinutes: 25,
          difficultyScore: 3,
          difficultyComment: '',
          issues: [],
          changesMade: [],
          overall: 4,
          taste: [],
          comment: 'おいしい',
          nextTimeIntent: [],
        ),
      );
      final controller = RecipeLibraryController(
        documents,
        tags,
        validator,
        () async => null,
        cookingStore: cooking,
        preparationStore: preparation,
        recipeVersionStateStore: versions,
        archiveStore: archive,
      );
      await controller.load();

      expect(await controller.deleteArchivedRecipe(id), contains('アーカイブ内'));
      await controller.setArchived(id, true);
      expect(await controller.deleteArchivedRecipe(id), contains('完全削除しました'));
      expect(controller.revisionsFor(id), isEmpty);
      expect(controller.latestRecipeFor(id), isNull);
      expect((await documents.loadDocuments()), hasLength(1));
      expect((await versions.loadActiveRevisions()).containsKey(id), isFalse);
      expect((await tags.loadTags()).containsKey(id), isFalse);
      expect((await tags.loadTags())['another-recipe-001'], ['休日']);
      expect(await preparation.checked(id, 1), isEmpty);
      expect((await cooking.read())['sessions'], isEmpty);
      expect(await archive.load(), isEmpty);
      expect(controller.recipes.single.id, 'another-recipe-001');
    },
  );

  test(
    'corrupt archive state blocks archive and delete without changing recipes',
    () async {
      final id = (first['recipe'] as Map<String, dynamic>)['id'] as String;
      final documents = FileRecipeDocumentStore(
        File('${directory.path}/recipes.json'),
      );
      await documents.saveDocument(first);
      final archiveFile = File('${directory.path}/archive.json');
      await archiveFile.writeAsString('{broken');
      final controller = RecipeLibraryController(
        documents,
        FileRecipeTagStore(File('${directory.path}/tags.json')),
        validator,
        () async => null,
        archiveStore: RecipeArchiveStore(archiveFile),
      );
      await controller.load();
      expect(controller.loadError, contains('アーカイブ'));
      expect(await controller.setArchived(id, true), contains('変更していません'));
      expect(await controller.deleteArchivedRecipe(id), contains('アーカイブ内'));
      expect(await documents.loadDocuments(), hasLength(1));
    },
  );

  test('unreadable cooking data stops deletion before any write', () async {
    final id = (first['recipe'] as Map<String, dynamic>)['id'] as String;
    final documents = FileRecipeDocumentStore(
      File('${directory.path}/recipes.json'),
    );
    final tags = FileRecipeTagStore(File('${directory.path}/tags.json'));
    final archive = RecipeArchiveStore(File('${directory.path}/archive.json'));
    final cookingFile = File('${directory.path}/cooking.json');
    await documents.saveDocument(first);
    await tags.saveTags(id, ['平日']);
    await archive.setArchived(id, true);
    await cookingFile.writeAsString('{broken');
    final controller = RecipeLibraryController(
      documents,
      tags,
      validator,
      () async => null,
      cookingStore: CookingStore(cookingFile, validator),
      recipeVersionStateStore: FileRecipeVersionStateStore(
        File('${directory.path}/versions.json'),
      ),
      archiveStore: archive,
    );
    await controller.load();

    expect(await controller.deleteArchivedRecipe(id), contains('削除していません'));
    expect(await documents.loadDocuments(), hasLength(1));
    expect((await tags.loadTags())[id], ['平日']);
    expect(await archive.load(), {id});
    expect(await cookingFile.readAsString(), '{broken');
  });
}
