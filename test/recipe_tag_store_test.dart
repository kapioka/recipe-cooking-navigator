import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_cooking_navigator/data/recipe_tag_store.dart';

void main() {
  late Directory temporaryDirectory;
  late FileRecipeTagStore store;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'recipe-tag-store-test-',
    );
    store = FileRecipeTagStore(
      File('${temporaryDirectory.path}/recipe-tags-v1.json'),
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('persists and removes tags by recipe ID', () async {
    await store.saveTags('recipe-1', ['時短', '和食']);

    final reopened = FileRecipeTagStore(store.file);
    expect(await reopened.loadTags(), {
      'recipe-1': ['時短', '和食'],
    });

    await reopened.saveTags('recipe-1', const []);
    expect(await reopened.loadTags(), isEmpty);
  });

  test('rejects invalid tags before writing', () async {
    await expectLater(
      store.saveTags('recipe-1', ['ＡＢＣ', 'abc']),
      throwsA(isA<RecipeTagStorageException>()),
    );
    await expectLater(
      store.saveTags('', ['時短']),
      throwsA(isA<RecipeTagStorageException>()),
    );
    await expectLater(
      store.saveTags('recipe-1', List.generate(6, (index) => 'タグ$index')),
      throwsA(isA<RecipeTagStorageException>()),
    );
    expect(await store.file.exists(), isFalse);
  });

  test(
    'rejects duplicate recipe ID entries without changing the file',
    () async {
      await store.file.writeAsString(
        jsonEncode({
          'storage_version': 1,
          'recipe_tags': [
            {
              'recipe_id': 'recipe-1',
              'tags': ['時短'],
            },
            {
              'recipe_id': 'recipe-1',
              'tags': ['和食'],
            },
          ],
        }),
      );

      await expectLater(
        store.loadTags(),
        throwsA(isA<RecipeTagStorageException>()),
      );
      expect(await store.file.exists(), isTrue);
    },
  );
}
