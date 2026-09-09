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

  test('preserves receipts from concurrent additions', () async {
    const first = RecipeInboxReceipt(
      documentId: 'drive-document-1',
      sha256:
          '1111111111111111111111111111111111111111111111111111111111111111',
      recipeId: 'recipe-1',
      revision: 1,
    );
    const second = RecipeInboxReceipt(
      documentId: 'drive-document-2',
      sha256:
          '2222222222222222222222222222222222222222222222222222222222222222',
      recipeId: 'recipe-2',
      revision: 1,
    );

    await Future.wait([
      store.addReceipts(const <RecipeInboxReceipt>[first]),
      store.addReceipts(const <RecipeInboxReceipt>[second]),
    ]);

    final reopened = await FileRecipeInboxStateStore(store.file).load();
    expect(
      reopened.receipts.map((receipt) => receipt.documentId),
      containsAll(<String>['drive-document-1', 'drive-document-2']),
    );
  });

  test('preserves folder and receipts during concurrent mutations', () async {
    const folder = RecipeInboxFolder(
      treeUri: 'content://provider/tree/inbox',
      displayName: 'Inbox',
    );
    const receipt = RecipeInboxReceipt(
      documentId: 'drive-document',
      sha256:
          '3333333333333333333333333333333333333333333333333333333333333333',
      recipeId: 'recipe-1',
      revision: 1,
    );

    await Future.wait([
      store.saveFolder(folder),
      store.addReceipts(const <RecipeInboxReceipt>[receipt]),
    ]);

    final reopened = await FileRecipeInboxStateStore(store.file).load();
    expect(reopened.folder?.treeUri, folder.treeUri);
    expect(reopened.receipts.single.documentId, receipt.documentId);
  });

  test('rejects an invalid folder before changing saved state', () async {
    const validFolder = RecipeInboxFolder(
      treeUri: 'content://provider/tree/inbox',
      displayName: 'Inbox',
    );
    await store.saveFolder(validFolder);

    await expectLater(
      store.saveFolder(
        const RecipeInboxFolder(treeUri: '', displayName: 'Inbox'),
      ),
      throwsA(isA<RecipeInboxStateStorageException>()),
    );

    final reopened = await FileRecipeInboxStateStore(store.file).load();
    expect(reopened.folder?.treeUri, validFolder.treeUri);
  });

  test('rejects an invalid receipt before changing saved state', () async {
    await expectLater(
      store.addReceipts(const <RecipeInboxReceipt>[
        RecipeInboxReceipt(
          documentId: 'drive-document',
          sha256: 'invalid',
          recipeId: 'recipe-1',
          revision: 1,
        ),
      ]),
      throwsA(isA<RecipeInboxStateStorageException>()),
    );

    expect((await store.load()).receipts, isEmpty);
  });
}
