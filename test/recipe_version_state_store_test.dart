import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_cooking_navigator/data/recipe_version_state_store.dart';

void main() {
  late Directory temporaryDirectory;
  late File stateFile;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'recipe-version-state-test-',
    );
    stateFile = File('${temporaryDirectory.path}/recipe-version-state-v1.json');
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('persists active revisions without recipe documents', () async {
    final store = FileRecipeVersionStateStore(stateFile);

    await store.saveActiveRevision('recipe-one', 2);
    await store.saveActiveRevision('recipe-two', 4);

    final reopened = FileRecipeVersionStateStore(stateFile);
    expect(await reopened.loadActiveRevisions(), {
      'recipe-one': 2,
      'recipe-two': 4,
    });
    final decoded = jsonDecode(await stateFile.readAsString()) as Map;
    expect(decoded['storage_version'], 1);
    expect(decoded.containsKey('recipes'), isFalse);
  });

  test('serializes concurrent updates for different recipes', () async {
    final store = FileRecipeVersionStateStore(stateFile);

    await Future.wait([
      store.saveActiveRevision('recipe-one', 2),
      store.saveActiveRevision('recipe-two', 3),
      store.saveActiveRevision('recipe-three', 1),
    ]);

    expect(await store.loadActiveRevisions(), {
      'recipe-one': 2,
      'recipe-two': 3,
      'recipe-three': 1,
    });
  });

  test('fails closed when the saved state is malformed', () async {
    await stateFile.writeAsString(
      jsonEncode({
        'storage_version': 1,
        'active_revisions': {'recipe-one': 0},
      }),
    );
    final original = await stateFile.readAsString();
    final store = FileRecipeVersionStateStore(stateFile);

    await expectLater(
      store.loadActiveRevisions(),
      throwsA(isA<RecipeVersionStateStorageException>()),
    );
    expect(await stateFile.readAsString(), original);
  });
}
