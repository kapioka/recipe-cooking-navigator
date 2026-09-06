import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_cooking_navigator/application/recipe_library_controller.dart';
import 'package:recipe_cooking_navigator/data/recipe_document_store.dart';
import 'package:recipe_cooking_navigator/data/recipe_tag_store.dart';
import 'package:recipe_cooking_navigator/domain/recipe_validator.dart';

void main() {
  late RecipeValidator validator;
  late Map<String, dynamic> revisionOne;

  setUpAll(() async {
    validator = RecipeValidator.fromSchemaString(
      await File('schemas/recipe-v1.schema.json').readAsString(),
    );
    revisionOne = jsonDecode(
      await File('examples/recipe-example.json').readAsString(),
    ) as Map<String, dynamic>;
  });

  test('shows the highest imported revision for each recipe ID', () async {
    final revisionTwo =
        jsonDecode(jsonEncode(revisionOne)) as Map<String, dynamic>;
    final recipe = revisionTwo['recipe'] as Map<String, dynamic>;
    recipe['revision'] = 2;
    recipe['parent_revision'] = 1;
    final store = _MemoryRecipeDocumentStore([revisionOne, revisionTwo]);
    final controller = RecipeLibraryController(
      store,
      _MemoryRecipeTagStore(),
      validator,
      () async => null,
    );

    await controller.load();

    expect(controller.recipes, hasLength(1));
    expect(controller.recipes.single.revision, 2);
  });

  test('does not save a malformed recipe selected from a file', () async {
    final store = _MemoryRecipeDocumentStore();
    final controller = RecipeLibraryController(
      store,
      _MemoryRecipeTagStore(),
      validator,
      () async => '{not valid',
    );

    final result = await controller.importFromFile();

    expect(result.status, RecipeImportStatus.failed);
    expect(store.documents, isEmpty);
  });

  test('searches titles, ingredients, and tags by substring', () async {
    final recipeId =
        (revisionOne['recipe'] as Map<String, dynamic>)['id'] as String;
    final tagStore = _MemoryRecipeTagStore({
      recipeId: ['時短', 'ＡＢＣ'],
    });
    final controller = RecipeLibraryController(
      _MemoryRecipeDocumentStore([revisionOne]),
      tagStore,
      validator,
      () async => null,
    );
    await controller.load();

    controller.setSearchQuery('生姜');
    expect(controller.recipes, hasLength(1));
    expect(
      controller.searchSuggestions.any(
        (suggestion) =>
            suggestion.kind == RecipeSearchSuggestionKind.recipeTitle,
      ),
      isTrue,
    );

    controller.setSearchQuery('こま');
    expect(controller.recipes, hasLength(1));
    expect(
      controller.searchSuggestions.single.kind,
      RecipeSearchSuggestionKind.ingredient,
    );

    controller.setSearchQuery('時');
    expect(controller.recipes, hasLength(1));
    expect(
      controller.searchSuggestions.single.kind,
      RecipeSearchSuggestionKind.tag,
    );

    controller.setSearchQuery('abc');
    expect(controller.recipes, hasLength(1));
    expect(controller.searchSuggestions.single.label, 'ＡＢＣ');

    controller.setSearchQuery('一致しない');
    expect(controller.recipes, isEmpty);
    controller.setSearchQuery('');
    expect(controller.recipes, hasLength(1));
  });

  test('normalizes, deduplicates, persists, and removes tags', () async {
    final recipeId =
        (revisionOne['recipe'] as Map<String, dynamic>)['id'] as String;
    final tagStore = _MemoryRecipeTagStore();
    final store = _MemoryRecipeDocumentStore([revisionOne]);
    final controller = RecipeLibraryController(
      store,
      tagStore,
      validator,
      () async => null,
    );
    await controller.load();

    final saved = await controller.setTags(recipeId, [
      ' 時短 ',
      '時短',
      '',
      'ＡＢＣ',
      'abc',
    ]);

    expect(saved.status, RecipeTagSaveStatus.saved);
    expect(controller.tagsFor(recipeId), ['時短', 'ＡＢＣ']);

    final reopened = RecipeLibraryController(
      store,
      tagStore,
      validator,
      () async => null,
    );
    await reopened.load();
    expect(reopened.tagsFor(recipeId), ['時短', 'ＡＢＣ']);

    await reopened.setTags(recipeId, const []);
    expect(reopened.tagsFor(recipeId), isEmpty);
    expect(tagStore.tagsByRecipeId, isEmpty);
  });

  test('rejects more than five unique tags', () async {
    final recipeId =
        (revisionOne['recipe'] as Map<String, dynamic>)['id'] as String;
    final tagStore = _MemoryRecipeTagStore();
    final controller = RecipeLibraryController(
      _MemoryRecipeDocumentStore([revisionOne]),
      tagStore,
      validator,
      () async => null,
    );
    await controller.load();

    final result = await controller.setTags(
      recipeId,
      List.generate(6, (index) => 'タグ$index'),
    );

    expect(result.status, RecipeTagSaveStatus.tooMany);
    expect(tagStore.tagsByRecipeId, isEmpty);
  });
}

class _MemoryRecipeDocumentStore implements RecipeDocumentStore {
  _MemoryRecipeDocumentStore([List<Map<String, dynamic>>? initial])
    : documents = [...?initial];

  final List<Map<String, dynamic>> documents;

  @override
  Future<List<Map<String, dynamic>>> loadDocuments() async => [...documents];

  @override
  Future<StoreRecipeResult> saveDocument(Map<String, dynamic> document) async {
    documents.add(document);
    return StoreRecipeResult.added;
  }
}

class _MemoryRecipeTagStore implements RecipeTagStore {
  _MemoryRecipeTagStore([Map<String, List<String>>? initial])
    : tagsByRecipeId = {
        for (final entry
            in initial?.entries ?? const <MapEntry<String, List<String>>>[])
          entry.key: [...entry.value],
      };

  final Map<String, List<String>> tagsByRecipeId;

  @override
  Future<Map<String, List<String>>> loadTags() async => {
    for (final entry in tagsByRecipeId.entries) entry.key: [...entry.value],
  };

  @override
  Future<void> saveTags(String recipeId, List<String> tags) async {
    if (tags.isEmpty) {
      tagsByRecipeId.remove(recipeId);
    } else {
      tagsByRecipeId[recipeId] = [...tags];
    }
  }
}
