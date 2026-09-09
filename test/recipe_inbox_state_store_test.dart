import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_cooking_navigator/data/recipe_inbox_state_store.dart';
import 'package:recipe_cooking_navigator/domain/recipe_inbox.dart';

void main() {
  late Directory temporaryDirectory;
  late FileRecipeInboxStateStore store;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'recipe-inbox-state-test-',
    );
    store = FileRecipeInboxStateStore(
      File('${temporaryDirectory.path}/recipe-inbox-v1.json'),
    );
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test('persists the selected folder and import receipts', () async {
    const folder = RecipeInboxFolder(
      treeUri: 'content://provider/tree/inbox',
      displayName: 'Inbox',
    );
    const receipt = RecipeInboxReceipt(
      documentId: 'drive-document-1',
      sha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      recipeId: 'recipe-1',
      revision: 2,
    );

    await store.saveFolder(folder);
    await store.addReceipts(const [receipt, receipt]);

    final reopened = await FileRecipeInboxStateStore(store.file).load();
    expect(reopened.folder?.treeUri, folder.treeUri);
    expect(reopened.folder?.displayName, 'Inbox');
    expect(reopened.receipts, hasLength(1));
    expect(reopened.receipts.single.documentId, 'drive-document-1');
    expect(reopened.receipts.single.revision, 2);
  });

  test('fails closed when saved state is malformed', () async {
    await store.file.parent.create(recursive: true);
    await store.file.writeAsString('{not valid');

    await expectLater(
      store.load(),
      throwsA(isA<RecipeInboxStateStorageException>()),
    );
    expect(await store.file.readAsString(), '{not valid');
  });
}
