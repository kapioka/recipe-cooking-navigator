import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_cooking_navigator/application/recipe_library_controller.dart';
import 'package:recipe_cooking_navigator/data/recipe_document_store.dart';
import 'package:recipe_cooking_navigator/data/recipe_inbox_state_store.dart';
import 'package:recipe_cooking_navigator/data/recipe_tag_store.dart';
import 'package:recipe_cooking_navigator/domain/recipe_inbox.dart';
import 'package:recipe_cooking_navigator/domain/recipe_validator.dart';

void main() {
  late RecipeValidator validator;
  late String recipeSource;

  setUpAll(() async {
    validator = RecipeValidator.fromSchemaString(
      await File('schemas/recipe-v1.schema.json').readAsString(),
    );
    recipeSource = await File('examples/recipe-example.json').readAsString();
  });

  test(
    'imports valid files while rejecting invalid and unreadable files',
    () async {
      final documentStore = _MemoryRecipeDocumentStore();
      final inboxStateStore = _MemoryRecipeInboxStateStore.withFolder();
      final platform = _FakeRecipeInboxPlatform(
        files: <RecipeInboxFile>[
          RecipeInboxFile(
            documentId: 'document-1',
            name: 'valid.json',
            source: recipeSource,
            sha256: '1111111111111111111111111111111111111111111111111111111111111111',
          ),
          const RecipeInboxFile(
            documentId: 'document-2',
            name: 'invalid.json',
            source: '{not valid',
            sha256: '2222222222222222222222222222222222222222222222222222222222222222',
          ),
          const RecipeInboxFile(
            documentId: 'document-3',
            name: 'unreadable.json',
            readError: 'ファイルを読み込めませんでした。',
          ),
        ],
      );
      final controller = _controller(
        validator,
        documentStore,
        platform,
        inboxStateStore,
        recipeSource,
      );
      await controller.load();

      final result = await controller.checkInbox();

      expect(result.status, RecipeInboxRunStatus.completed);
      expect(result.importedCount, 1);
      expect(result.skippedCount, 0);
      expect(result.rejectedCount, 2);
      expect(documentStore.documents, hasLength(1));
      expect(inboxStateStore.state.receipts, hasLength(1));
    },
  );

  test('imports multiple valid files in one manual scan', () async {
    final second = jsonDecode(recipeSource) as Map<String, dynamic>;
    final secondRecipe = second['recipe'] as Map<String, dynamic>;
    secondRecipe['id'] = 'second-recipe-001';
    secondRecipe['title'] = '2件目のレシピ';
    final documentStore = _MemoryRecipeDocumentStore();
    final inboxStateStore = _MemoryRecipeInboxStateStore.withFolder();
    final controller = _controller(
      validator,
      documentStore,
      _FakeRecipeInboxPlatform(
        files: <RecipeInboxFile>[
          RecipeInboxFile(
            documentId: 'document-1',
            name: 'first.json',
            source: recipeSource,
            sha256: '1111111111111111111111111111111111111111111111111111111111111111',
          ),
          RecipeInboxFile(
            documentId: 'document-2',
            name: 'second.json',
            source: jsonEncode(second),
            sha256: '2222222222222222222222222222222222222222222222222222222222222222',
          ),
        ],
      ),
      inboxStateStore,
      recipeSource,
    );
    await controller.load();

    final result = await controller.checkInbox();

    expect(result.importedCount, 2);
    expect(result.rejectedCount, 0);
    expect(documentStore.documents, hasLength(2));
    expect(inboxStateStore.state.receipts, hasLength(2));
  });

  test(
    'skips a previously received document without saving it again',
    () async {
      final documentStore = _MemoryRecipeDocumentStore();
      final inboxStateStore = _MemoryRecipeInboxStateStore.withFolder();
      final platform = _FakeRecipeInboxPlatform(
        files: <RecipeInboxFile>[
          RecipeInboxFile(
            documentId: 'document-1',
            name: 'recipe.json',
            source: recipeSource,
            sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          ),
        ],
      );
      final controller = _controller(
        validator,
        documentStore,
        platform,
        inboxStateStore,
        recipeSource,
      );
      await controller.load();

      expect((await controller.checkInbox()).importedCount, 1);
      final repeated = await controller.checkInbox();

      expect(repeated.skippedCount, 1);
      expect(documentStore.documents, hasLength(1));
      expect(inboxStateStore.state.receipts, hasLength(1));
    },
  );

  test(
    'rejects a conflicting revision and does not record a receipt',
    () async {
      final existing = jsonDecode(recipeSource) as Map<String, dynamic>;
      final conflicting = jsonDecode(recipeSource) as Map<String, dynamic>;
      (conflicting['recipe'] as Map<String, dynamic>)['title'] = '異なる内容';
      final documentStore = _MemoryRecipeDocumentStore(<Map<String, dynamic>>[
        existing,
      ]);
      final inboxStateStore = _MemoryRecipeInboxStateStore.withFolder();
      final controller = _controller(
        validator,
        documentStore,
        _FakeRecipeInboxPlatform(
          files: <RecipeInboxFile>[
            RecipeInboxFile(
              documentId: 'document-conflict',
              name: 'conflict.json',
              source: jsonEncode(conflicting),
              sha256: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            ),
          ],
        ),
        inboxStateStore,
        recipeSource,
      );
      await controller.load();

      final result = await controller.checkInbox();

      expect(result.rejectedCount, 1);
      expect(documentStore.documents, hasLength(1));
      expect(inboxStateStore.state.receipts, isEmpty);
    },
  );

  test(
    'keeps single-file import available when Inbox needs selection',
    () async {
      final documentStore = _MemoryRecipeDocumentStore();
      final inboxStateStore = _MemoryRecipeInboxStateStore();
      final controller = _controller(
        validator,
        documentStore,
        _FakeRecipeInboxPlatform(files: const <RecipeInboxFile>[]),
        inboxStateStore,
        recipeSource,
      );
      await controller.load();

      final inboxResult = await controller.checkInbox();
      final fileResult = await controller.importFromFile();

      expect(inboxResult.status, RecipeInboxRunStatus.folderSelectionRequired);
      expect(fileResult.status, RecipeImportStatus.imported);
      expect(documentStore.documents, hasLength(1));
    },
  );

  test(
    'skips the same recipe imported through the single-file route',
    () async {
      final documentStore = _MemoryRecipeDocumentStore();
      final inboxStateStore = _MemoryRecipeInboxStateStore.withFolder();
      final controller = _controller(
        validator,
        documentStore,
        _FakeRecipeInboxPlatform(
          files: <RecipeInboxFile>[
            RecipeInboxFile(
              documentId: 'document-after-file-import',
              name: 'recipe.json',
              source: recipeSource,
              sha256: 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
            ),
          ],
        ),
        inboxStateStore,
        recipeSource,
      );
      await controller.load();

      expect(
        (await controller.importFromFile()).status,
        RecipeImportStatus.imported,
      );
      final inboxResult = await controller.checkInbox();

      expect(inboxResult.skippedCount, 1);
      expect(documentStore.documents, hasLength(1));
      expect(inboxStateStore.state.receipts, hasLength(1));
    },
  );

  test(
    'requests reselection without clearing recipes after permission loss',
    () async {
      final existing = jsonDecode(recipeSource) as Map<String, dynamic>;
      final documentStore = _MemoryRecipeDocumentStore(<Map<String, dynamic>>[
        existing,
      ]);
      final controller = _controller(
        validator,
        documentStore,
        _FakeRecipeInboxPlatform(
          files: const <RecipeInboxFile>[],
          readError: const RecipeInboxException(
            'permission_lost',
            'Inboxフォルダのアクセス権が失われました。',
          ),
        ),
        _MemoryRecipeInboxStateStore.withFolder(),
        recipeSource,
      );
      await controller.load();

      final result = await controller.checkInbox();

      expect(result.status, RecipeInboxRunStatus.folderSelectionRequired);
      expect(controller.recipes, hasLength(1));
    },
  );
}

RecipeLibraryController _controller(
  RecipeValidator validator,
  RecipeDocumentStore documentStore,
  RecipeInboxPlatform platform,
  RecipeInboxStateStore stateStore,
  String pickedSource,
) {
  return RecipeLibraryController(
    documentStore,
    _MemoryRecipeTagStore(),
    validator,
    () async => pickedSource,
    recipeInboxPlatform: platform,
    recipeInboxStateStore: stateStore,
  );
}

class _FakeRecipeInboxPlatform implements RecipeInboxPlatform {
  _FakeRecipeInboxPlatform({required this.files, this.readError});

  final List<RecipeInboxFile> files;
  final RecipeInboxException? readError;

  @override
  Future<List<RecipeInboxFile>> readFiles(RecipeInboxFolder folder) async {
    if (readError case final error?) {
      throw error;
    }
    return files;
  }

  @override
  Future<RecipeInboxFolder?> selectFolder() async => const RecipeInboxFolder(
    treeUri: 'content://provider/tree/inbox',
    displayName: 'Inbox',
  );
}

class _MemoryRecipeInboxStateStore implements RecipeInboxStateStore {
  _MemoryRecipeInboxStateStore() : state = RecipeInboxState.empty;

  _MemoryRecipeInboxStateStore.withFolder()
    : state = const RecipeInboxState(
        folder: RecipeInboxFolder(
          treeUri: 'content://provider/tree/inbox',
          displayName: 'Inbox',
        ),
        receipts: <RecipeInboxReceipt>[],
      );

  RecipeInboxState state;

  @override
  Future<void> addReceipts(Iterable<RecipeInboxReceipt> receipts) async {
    final byKey = <String, RecipeInboxReceipt>{
      for (final receipt in state.receipts) receipt.contentKey: receipt,
      for (final receipt in receipts) receipt.contentKey: receipt,
    };
    state = RecipeInboxState(
      folder: state.folder,
      receipts: byKey.values.toList(),
    );
  }

  @override
  Future<RecipeInboxState> load() async => state;

  @override
  Future<void> saveFolder(RecipeInboxFolder folder) async {
    state = RecipeInboxState(folder: folder, receipts: state.receipts);
  }
}

class _MemoryRecipeDocumentStore implements RecipeDocumentStore {
  _MemoryRecipeDocumentStore([List<Map<String, dynamic>>? initial])
    : documents = <Map<String, dynamic>>[...?initial];

  final List<Map<String, dynamic>> documents;

  @override
  Future<List<Map<String, dynamic>>> loadDocuments() async => [...documents];

  @override
  Future<StoreRecipeResult> saveDocument(Map<String, dynamic> document) async {
    final recipe = document['recipe'] as Map<String, dynamic>;
    for (final existing in documents) {
      final existingRecipe = existing['recipe'] as Map<String, dynamic>;
      if (existingRecipe['id'] == recipe['id'] &&
          existingRecipe['revision'] == recipe['revision']) {
        return const DeepCollectionEquality().equals(existing, document)
            ? StoreRecipeResult.alreadyExists
            : StoreRecipeResult.conflictingRevision;
      }
    }
    documents.add(document);
    return StoreRecipeResult.added;
  }
}

class _MemoryRecipeTagStore implements RecipeTagStore {
  @override
  Future<Map<String, List<String>>> loadTags() async =>
      <String, List<String>>{};

  @override
  Future<void> saveTags(String recipeId, List<String> tags) async {}
}
