import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_cooking_navigator/application/recipe_library_controller.dart';
import 'package:recipe_cooking_navigator/data/recipe_document_store.dart';
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
      validator,
      () async => '{not valid',
    );

    final result = await controller.importFromFile();

    expect(result.status, RecipeImportStatus.failed);
    expect(store.documents, isEmpty);
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
