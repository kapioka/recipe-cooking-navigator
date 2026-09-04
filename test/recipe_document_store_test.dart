import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_cooking_navigator/data/recipe_document_store.dart';

void main() {
  late Directory temporaryDirectory;
  late FileRecipeDocumentStore store;
  late Map<String, dynamic> recipeDocument;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'recipe-cooking-navigator-test-',
    );
    store = FileRecipeDocumentStore(
      File('${temporaryDirectory.path}/recipes-v1.json'),
    );
    recipeDocument = jsonDecode(
      await File('examples/recipe-example.json').readAsString(),
    ) as Map<String, dynamic>;
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('persists a recipe and loads it from a new store instance', () async {
    expect(await store.saveDocument(recipeDocument), StoreRecipeResult.added);

    final reopened = FileRecipeDocumentStore(store.file);
    final loaded = await reopened.loadDocuments();

    expect(loaded, hasLength(1));
    expect(
      (loaded.single['recipe'] as Map<String, dynamic>)['title'],
      '豚の生姜焼き',
    );
  });

  test('treats an identical recipe revision as already saved', () async {
    await store.saveDocument(recipeDocument);

    expect(
      await store.saveDocument(recipeDocument),
      StoreRecipeResult.alreadyExists,
    );
    expect(await store.loadDocuments(), hasLength(1));
  });

  test('appends a new revision without losing the previous one', () async {
    await store.saveDocument(recipeDocument);
    final revisionTwo =
        jsonDecode(jsonEncode(recipeDocument)) as Map<String, dynamic>;
    final recipe = revisionTwo['recipe'] as Map<String, dynamic>;
    recipe['revision'] = 2;
    recipe['parent_revision'] = 1;

    expect(await store.saveDocument(revisionTwo), StoreRecipeResult.added);
    final loaded = await store.loadDocuments();
    expect(loaded, hasLength(2));
    expect(
      loaded.map(
        (document) => (document['recipe'] as Map<String, dynamic>)['revision'],
      ),
      [1, 2],
    );
  });

  test('does not overwrite different content with the same identity', () async {
    await store.saveDocument(recipeDocument);
    final changed =
        jsonDecode(jsonEncode(recipeDocument)) as Map<String, dynamic>;
    (changed['recipe'] as Map<String, dynamic>)['title'] = '別の内容';

    expect(
      await store.saveDocument(changed),
      StoreRecipeResult.conflictingRevision,
    );
    final loaded = await store.loadDocuments();
    expect(
      (loaded.single['recipe'] as Map<String, dynamic>)['title'],
      '豚の生姜焼き',
    );
  });
}
