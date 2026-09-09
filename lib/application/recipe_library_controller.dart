import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/cooking_store.dart';
import '../data/recipe_document_store.dart';
import '../data/recipe_inbox_state_store.dart';
import '../data/recipe_tag_store.dart';
import '../data/recipe_version_state_store.dart';
import '../domain/recipe_document.dart';
import '../domain/recipe_inbox.dart';
import '../domain/recipe_validator.dart';
import '../domain/search_text.dart';

typedef RecipeSourcePicker = Future<String?> Function();

enum RecipeImportStatus { imported, alreadyExists, cancelled, failed }

class RecipeImportResult {
  const RecipeImportResult(this.status, this.message);

  final RecipeImportStatus status;
  final String message;
}

enum ActiveRevisionUpdateStatus { updated, alreadyActive, notFound, failed }

class ActiveRevisionUpdateResult {
  const ActiveRevisionUpdateResult(this.status, this.message);

  final ActiveRevisionUpdateStatus status;
  final String message;
}

enum RecipeInboxFolderSelectionStatus { selected, cancelled, failed }

class RecipeInboxFolderSelectionResult {
  const RecipeInboxFolderSelectionResult(this.status, this.message);

  final RecipeInboxFolderSelectionStatus status;
  final String message;
}

enum RecipeInboxRunStatus { completed, folderSelectionRequired, failed }

enum RecipeInboxFileStatus { imported, skipped, rejected }

class RecipeInboxFileResult {
  const RecipeInboxFileResult({
    required this.fileName,
    required this.status,
    required this.message,
  });

  final String fileName;
  final RecipeInboxFileStatus status;
  final String message;
}

class RecipeInboxRunResult {
  const RecipeInboxRunResult({
    required this.status,
    required this.message,
    this.files = const <RecipeInboxFileResult>[],
  });

  final RecipeInboxRunStatus status;
  final String message;
  final List<RecipeInboxFileResult> files;

  int get importedCount => files
      .where((file) => file.status == RecipeInboxFileStatus.imported)
      .length;
  int get skippedCount => files
      .where((file) => file.status == RecipeInboxFileStatus.skipped)
      .length;
  int get rejectedCount => files
      .where((file) => file.status == RecipeInboxFileStatus.rejected)
      .length;
}

enum RecipeTagSaveStatus { saved, tooMany, failed }

class RecipeTagSaveResult {
  const RecipeTagSaveResult(this.status, this.message);

  final RecipeTagSaveStatus status;
  final String message;
}

enum RecipeSearchSuggestionKind { recipeTitle, ingredient, tag }

class RecipeSearchSuggestion {
  const RecipeSearchSuggestion({required this.label, required this.kind});

  final String label;
  final RecipeSearchSuggestionKind kind;
}

class RecipeLibraryController extends ChangeNotifier {
  RecipeLibraryController(
    this._store,
    this._tagStore,
    this._validator,
    this._pickRecipeSource, {
    CookingStore? cookingStore,
    RecipeInboxPlatform? recipeInboxPlatform,
    RecipeInboxStateStore? recipeInboxStateStore,
    RecipeVersionStateStore? recipeVersionStateStore,
  }) : assert(
         (recipeInboxPlatform == null) == (recipeInboxStateStore == null),
         'Inbox platform and state store must be provided together.',
       ),
       cookingStore = cookingStore ?? CookingStore(),
       _recipeInboxPlatform = recipeInboxPlatform,
       _recipeInboxStateStore = recipeInboxStateStore,
       _recipeVersionStateStore =
           recipeVersionStateStore ?? MemoryRecipeVersionStateStore();

  final CookingStore cookingStore;

  RecipeDocument? revisionFor(String id, int revision) {
    for (final document in _documents) {
      if (document.id == id && document.revision == revision) return document;
    }
    return null;
  }

  List<RecipeDocument> revisionsFor(String id) {
    final revisions =
        _documents
            .where((document) => document.id == id)
            .toList(growable: false)
          ..sort((a, b) => b.revision.compareTo(a.revision));
    return List.unmodifiable(revisions);
  }

  RecipeDocument? latestRecipeFor(String id) {
    for (final document in _latestRecipes) {
      if (document.id == id) return document;
    }
    return null;
  }

  RecipeDocument? activeRecipeFor(String id) {
    final latest = latestRecipeFor(id);
    if (latest == null) return null;
    final selectedRevision = _activeRevisionsByRecipeId[id];
    return selectedRevision == null
        ? latest
        : revisionFor(id, selectedRevision) ?? latest;
  }

  bool isActiveRevision(String id, int revision) =>
      activeRecipeFor(id)?.revision == revision;

  bool isLatestRevision(String id, int revision) =>
      latestRecipeFor(id)?.revision == revision;

  final RecipeDocumentStore _store;
  final RecipeTagStore _tagStore;
  final RecipeValidator _validator;
  final RecipeSourcePicker _pickRecipeSource;
  final RecipeInboxPlatform? _recipeInboxPlatform;
  final RecipeInboxStateStore? _recipeInboxStateStore;
  final RecipeVersionStateStore _recipeVersionStateStore;

  List<RecipeDocument> _documents = const [];
  List<RecipeDocument> _latestRecipes = const [];
  List<RecipeDocument> _activeRecipes = const [];
  List<RecipeDocument> _visibleRecipes = const [];
  Map<String, int> _activeRevisionsByRecipeId = const {};
  Map<String, List<String>> _tagsByRecipeId = const {};
  List<RecipeSearchSuggestion> _searchSuggestions = const [];
  String _searchQuery = '';
  bool _isImporting = false;
  bool _isCheckingInbox = false;
  bool _isSelectingInboxFolder = false;
  Future<RecipeInboxRunResult>? _activeInboxCheck;
  Future<void> _libraryMutationTail = Future<void>.value();
  RecipeInboxFolder? _inboxFolder;
  String? _loadError;
  String? _versionStateLoadError;
  bool _versionStateReadable = true;

  List<RecipeDocument> get recipes => _visibleRecipes;
  int get totalRecipeCount => _activeRecipes.length;
  String get searchQuery => _searchQuery;
  List<RecipeSearchSuggestion> get searchSuggestions => _searchSuggestions;
  bool get isImporting => _isImporting;
  bool get isCheckingInbox => _isCheckingInbox;
  bool get isSelectingInboxFolder => _isSelectingInboxFolder;
  bool get isInboxBusy => _isCheckingInbox || _isSelectingInboxFolder;
  bool get isBusy => _isImporting || isInboxBusy;
  RecipeInboxFolder? get inboxFolder => _inboxFolder;
  String? get loadError {
    final messages = <String>[?_loadError, ?_versionStateLoadError];
    return messages.isEmpty ? null : messages.join('\n');
  }

  List<String> tagsFor(String recipeId) {
    return _tagsByRecipeId[recipeId] ?? const [];
  }

  Future<void> load() async {
    try {
      final stored = await _store.loadDocuments();
      _documents = stored
          .map(_validator.validateDocument)
          .toList(growable: false);
      _rebuildLatestRecipes();
      _loadError = null;
      _versionStateLoadError = null;
    } catch (error) {
      _documents = const [];
      _latestRecipes = const [];
      _activeRecipes = const [];
      _visibleRecipes = const [];
      _activeRevisionsByRecipeId = const {};
      _tagsByRecipeId = const {};
      _searchSuggestions = const [];
      _loadError = error is RecipeStorageException
          ? error.message
          : '保存済みレシピを読み込めませんでした。';
      _versionStateLoadError = null;
      notifyListeners();
      return;
    }

    try {
      final storedActiveRevisions = await _recipeVersionStateStore
          .loadActiveRevisions();
      _versionStateReadable = true;
      _activeRevisionsByRecipeId = Map.unmodifiable(storedActiveRevisions);
      _rebuildActiveRecipes();
      _refreshVersionStateLoadError();
    } on RecipeVersionStateStorageException catch (error) {
      _versionStateReadable = false;
      _activeRevisionsByRecipeId = const {};
      _rebuildActiveRecipes();
      _versionStateLoadError = error.message;
    } catch (_) {
      _versionStateReadable = false;
      _activeRevisionsByRecipeId = const {};
      _rebuildActiveRecipes();
      _versionStateLoadError = 'active Versionの保存状態を読み込めませんでした。';
    }

    try {
      _tagsByRecipeId = await _tagStore.loadTags();
      _rebuildSearch();
    } catch (error) {
      _tagsByRecipeId = const {};
      _rebuildSearch();
      _loadError = error is RecipeTagStorageException
          ? error.message
          : '保存済みタグを読み込めませんでした。';
    }

    final inboxStateStore = _recipeInboxStateStore;
    if (inboxStateStore != null) {
      try {
        _inboxFolder = (await inboxStateStore.load()).folder;
      } on RecipeInboxStateStorageException catch (error) {
        _inboxFolder = null;
        _loadError ??= error.message;
      } catch (_) {
        _inboxFolder = null;
        _loadError ??= 'Inboxの接続情報を読み込めませんでした。';
      }
    }
    notifyListeners();
  }

  Future<RecipeImportResult> importFromFile() async {
    _isImporting = true;
    notifyListeners();

    try {
      final source = await _pickRecipeSource();
      if (source == null) {
        return const RecipeImportResult(
          RecipeImportStatus.cancelled,
          '取り込みをキャンセルしました。',
        );
      }
      return await importSource(source);
    } on RecipeImportException catch (error) {
      return RecipeImportResult(RecipeImportStatus.failed, error.message);
    } on RecipeStorageException catch (error) {
      return RecipeImportResult(RecipeImportStatus.failed, error.message);
    } catch (_) {
      return const RecipeImportResult(
        RecipeImportStatus.failed,
        'ファイルを読み込めませんでした。もう一度お試しください。',
      );
    } finally {
      _isImporting = false;
      notifyListeners();
    }
  }

  Future<RecipeInboxFolderSelectionResult> selectInboxFolder() async {
    final platform = _recipeInboxPlatform;
    final stateStore = _recipeInboxStateStore;
    if (platform == null || stateStore == null) {
      return const RecipeInboxFolderSelectionResult(
        RecipeInboxFolderSelectionStatus.failed,
        'この端末ではInboxフォルダを選択できません。',
      );
    }
    if (isInboxBusy) {
      return const RecipeInboxFolderSelectionResult(
        RecipeInboxFolderSelectionStatus.failed,
        'Inboxの処理中です。完了してからフォルダを選択してください。',
      );
    }

    _isSelectingInboxFolder = true;
    notifyListeners();
    try {
      final previousFolder = (await stateStore.load()).folder;
      final folder = await platform.selectFolder();
      if (folder == null) {
        return const RecipeInboxFolderSelectionResult(
          RecipeInboxFolderSelectionStatus.cancelled,
          'フォルダ選択をキャンセルしました。',
        );
      }
      await stateStore.saveFolder(folder);
      _inboxFolder = folder;

      String? releaseWarning;
      if (previousFolder != null && previousFolder.treeUri != folder.treeUri) {
        try {
          await platform.releaseFolder(previousFolder);
        } on RecipeInboxException catch (error) {
          releaseWarning = error.message;
        } catch (_) {
          releaseWarning = '以前のInboxフォルダのアクセス権を解除できませんでした。';
        }
      }
      return RecipeInboxFolderSelectionResult(
        RecipeInboxFolderSelectionStatus.selected,
        releaseWarning == null
            ? 'Google Driveの「${folder.displayName}」をInboxとして接続しました。'
            : 'Google Driveの「${folder.displayName}」を接続しました。\n$releaseWarning',
      );
    } on RecipeInboxException catch (error) {
      return RecipeInboxFolderSelectionResult(
        RecipeInboxFolderSelectionStatus.failed,
        error.message,
      );
    } on RecipeInboxStateStorageException catch (error) {
      return RecipeInboxFolderSelectionResult(
        RecipeInboxFolderSelectionStatus.failed,
        error.message,
      );
    } catch (_) {
      return const RecipeInboxFolderSelectionResult(
        RecipeInboxFolderSelectionStatus.failed,
        'Inboxフォルダを接続できませんでした。',
      );
    } finally {
      _isSelectingInboxFolder = false;
      notifyListeners();
    }
  }

  Future<RecipeInboxRunResult> checkInbox() {
    final active = _activeInboxCheck;
    if (active != null) {
      return active;
    }
    if (_isSelectingInboxFolder) {
      return Future<RecipeInboxRunResult>.value(
        const RecipeInboxRunResult(
          status: RecipeInboxRunStatus.failed,
          message: 'Inboxフォルダの選択中です。完了してから確認してください。',
        ),
      );
    }

    final operation = _checkInboxOnce();
    _activeInboxCheck = operation;
    unawaited(
      operation.whenComplete(() {
        if (identical(_activeInboxCheck, operation)) {
          _activeInboxCheck = null;
        }
      }),
    );
    return operation;
  }

  Future<RecipeInboxRunResult> _checkInboxOnce() async {
    final platform = _recipeInboxPlatform;
    final stateStore = _recipeInboxStateStore;
    if (platform == null || stateStore == null) {
      return const RecipeInboxRunResult(
        status: RecipeInboxRunStatus.failed,
        message: 'この端末ではInboxを利用できません。',
      );
    }

    _isCheckingInbox = true;
    notifyListeners();
    try {
      final state = await stateStore.load();
      final folder = state.folder;
      if (folder == null) {
        _inboxFolder = null;
        return const RecipeInboxRunResult(
          status: RecipeInboxRunStatus.folderSelectionRequired,
          message: '最初にGoogle DriveのInboxフォルダを選択してください。',
        );
      }
      _inboxFolder = folder;

      final inboxFiles = await platform.readFiles(folder);
      final receiptsByKey = <String, RecipeInboxReceipt>{
        for (final receipt in state.receipts) receipt.contentKey: receipt,
      };
      final newReceipts = <RecipeInboxReceipt>[];
      final fileResults = <RecipeInboxFileResult>[];

      for (final inboxFile in inboxFiles) {
        if (!inboxFile.isReadable) {
          fileResults.add(
            RecipeInboxFileResult(
              fileName: inboxFile.name,
              status: RecipeInboxFileStatus.rejected,
              message: inboxFile.readError ?? 'ファイルを読み込めませんでした。',
            ),
          );
          continue;
        }

        final contentKey = '${inboxFile.documentId}\u0000${inboxFile.sha256}';
        final priorReceipt = receiptsByKey[contentKey];
        if (priorReceipt != null &&
            revisionFor(priorReceipt.recipeId, priorReceipt.revision) != null) {
          fileResults.add(
            RecipeInboxFileResult(
              fileName: inboxFile.name,
              status: RecipeInboxFileStatus.skipped,
              message: '同一内容を確認済みです。',
            ),
          );
          continue;
        }

        try {
          final outcome = await _saveSource(inboxFile.source!);
          switch (outcome.storeResult) {
            case StoreRecipeResult.added:
              fileResults.add(
                RecipeInboxFileResult(
                  fileName: inboxFile.name,
                  status: RecipeInboxFileStatus.imported,
                  message: '「${outcome.document.title}」を取り込みました。',
                ),
              );
            case StoreRecipeResult.alreadyExists:
              fileResults.add(
                RecipeInboxFileResult(
                  fileName: inboxFile.name,
                  status: RecipeInboxFileStatus.skipped,
                  message:
                      '「${outcome.document.title}」のVersion ${outcome.document.revision}は保存済みです。',
                ),
              );
            case StoreRecipeResult.conflictingRevision:
              fileResults.add(
                RecipeInboxFileResult(
                  fileName: inboxFile.name,
                  status: RecipeInboxFileStatus.rejected,
                  message: '同じレシピIDとVersionで内容が異なります。',
                ),
              );
              continue;
          }

          final receipt = RecipeInboxReceipt(
            documentId: inboxFile.documentId,
            sha256: inboxFile.sha256!,
            recipeId: outcome.document.id,
            revision: outcome.document.revision,
          );
          receiptsByKey[receipt.contentKey] = receipt;
          newReceipts.add(receipt);
        } on RecipeImportException catch (error) {
          fileResults.add(
            RecipeInboxFileResult(
              fileName: inboxFile.name,
              status: RecipeInboxFileStatus.rejected,
              message: error.message,
            ),
          );
        } on RecipeStorageException catch (error) {
          fileResults.add(
            RecipeInboxFileResult(
              fileName: inboxFile.name,
              status: RecipeInboxFileStatus.rejected,
              message: error.message,
            ),
          );
        } catch (_) {
          fileResults.add(
            RecipeInboxFileResult(
              fileName: inboxFile.name,
              status: RecipeInboxFileStatus.rejected,
              message: 'ファイルを取り込めませんでした。',
            ),
          );
        }
      }

      String? receiptWarning;
      try {
        await stateStore.addReceipts(newReceipts);
      } on RecipeInboxStateStorageException catch (error) {
        receiptWarning = error.message;
      } catch (_) {
        receiptWarning = 'Inboxの取込記録を保存できませんでした。レシピ本体は保持しています。';
      }

      final provisional = RecipeInboxRunResult(
        status: RecipeInboxRunStatus.completed,
        message: '',
        files: List.unmodifiable(fileResults),
      );
      final summary =
          '${provisional.importedCount}件取り込み、'
          '${provisional.skippedCount}件保存済み、'
          '${provisional.rejectedCount}件拒否しました。';
      return RecipeInboxRunResult(
        status: RecipeInboxRunStatus.completed,
        message: receiptWarning == null ? summary : '$summary\n$receiptWarning',
        files: provisional.files,
      );
    } on RecipeInboxException catch (error) {
      if (error.requiresFolderSelection) {
        _inboxFolder = null;
      }
      return RecipeInboxRunResult(
        status: error.requiresFolderSelection
            ? RecipeInboxRunStatus.folderSelectionRequired
            : RecipeInboxRunStatus.failed,
        message: error.message,
      );
    } on RecipeInboxStateStorageException catch (error) {
      return RecipeInboxRunResult(
        status: RecipeInboxRunStatus.failed,
        message: error.message,
      );
    } catch (_) {
      return const RecipeInboxRunResult(
        status: RecipeInboxRunStatus.failed,
        message: 'Inboxを確認できませんでした。接続状態を確認してください。',
      );
    } finally {
      _isCheckingInbox = false;
      notifyListeners();
    }
  }

  @visibleForTesting
  Future<RecipeImportResult> importSource(String source) async {
    final outcome = await _saveSource(source);
    final document = outcome.document;

    switch (outcome.storeResult) {
      case StoreRecipeResult.added:
        return RecipeImportResult(
          RecipeImportStatus.imported,
          '「${document.title}」を取り込みました。',
        );
      case StoreRecipeResult.alreadyExists:
        return RecipeImportResult(
          RecipeImportStatus.alreadyExists,
          '「${document.title}」のVersion ${document.revision}は保存済みです。',
        );
      case StoreRecipeResult.conflictingRevision:
        return const RecipeImportResult(
          RecipeImportStatus.failed,
          '同じレシピIDとVersionで内容が異なるため、取り込みませんでした。',
        );
    }
  }

  Future<_RecipeSaveOutcome> _saveSource(String source) =>
      _synchronizeLibraryMutation(() async {
        final document = _validator.validateSource(source);
        final storeResult = await _store.saveDocument(document.raw);
        if (storeResult == StoreRecipeResult.added) {
          _documents = [..._documents, document];
          _rebuildLatestRecipes();
          notifyListeners();
        }
        return _RecipeSaveOutcome(document, storeResult);
      });

  Future<T> _synchronizeLibraryMutation<T>(Future<T> Function() action) {
    final previous = _libraryMutationTail;
    final release = Completer<void>();
    _libraryMutationTail = release.future;
    return () async {
      await previous;
      try {
        return await action();
      } finally {
        release.complete();
      }
    }();
  }

  void setSearchQuery(String query) {
    if (_searchQuery == query) {
      return;
    }
    _searchQuery = query;
    _rebuildSearch();
    notifyListeners();
  }

  Future<ActiveRevisionUpdateResult> setActiveRevision(
    String recipeId,
    int revision,
  ) => _synchronizeLibraryMutation(() async {
    final selected = revisionFor(recipeId, revision);
    if (selected == null) {
      return const ActiveRevisionUpdateResult(
        ActiveRevisionUpdateStatus.notFound,
        '選択したVersionが見つかりません。保存状態は変更していません。',
      );
    }
    if (isActiveRevision(recipeId, revision)) {
      return const ActiveRevisionUpdateResult(
        ActiveRevisionUpdateStatus.alreadyActive,
        'このVersionはすでにactiveです。',
      );
    }

    try {
      await _recipeVersionStateStore.saveActiveRevision(recipeId, revision);
      _activeRevisionsByRecipeId = Map.unmodifiable({
        ..._activeRevisionsByRecipeId,
        recipeId: revision,
      });
      _rebuildActiveRecipes();
      _versionStateReadable = true;
      _refreshVersionStateLoadError();
      notifyListeners();
      return ActiveRevisionUpdateResult(
        ActiveRevisionUpdateStatus.updated,
        'Version $revisionをactiveにしました。',
      );
    } on RecipeVersionStateStorageException catch (error) {
      return ActiveRevisionUpdateResult(
        ActiveRevisionUpdateStatus.failed,
        error.message,
      );
    } catch (_) {
      return const ActiveRevisionUpdateResult(
        ActiveRevisionUpdateStatus.failed,
        'active Versionを変更できませんでした。',
      );
    }
  });

  Future<RecipeTagSaveResult> setTags(
    String recipeId,
    Iterable<String> values,
  ) async {
    final uniqueTags = <String, String>{};
    for (final value in values) {
      final displayValue = value.trim();
      final normalized = normalizeSearchText(displayValue);
      if (normalized.isEmpty) {
        continue;
      }
      uniqueTags.putIfAbsent(normalized, () => displayValue);
    }

    if (uniqueTags.length > 5) {
      return const RecipeTagSaveResult(
        RecipeTagSaveStatus.tooMany,
        'タグは5個まで保存できます。',
      );
    }

    final tags = uniqueTags.values.toList(growable: false);
    try {
      await _tagStore.saveTags(recipeId, tags);
      final updated = Map<String, List<String>>.from(_tagsByRecipeId);
      if (tags.isEmpty) {
        updated.remove(recipeId);
      } else {
        updated[recipeId] = List.unmodifiable(tags);
      }
      _tagsByRecipeId = Map.unmodifiable(updated);
      _rebuildSearch();
      notifyListeners();
      return const RecipeTagSaveResult(RecipeTagSaveStatus.saved, 'タグを保存しました。');
    } on RecipeTagStorageException catch (error) {
      return RecipeTagSaveResult(RecipeTagSaveStatus.failed, error.message);
    } catch (_) {
      return const RecipeTagSaveResult(
        RecipeTagSaveStatus.failed,
        'タグを保存できませんでした。',
      );
    }
  }

  void _rebuildLatestRecipes() {
    final latestById = <String, RecipeDocument>{};
    for (final document in _documents) {
      final current = latestById[document.id];
      if (current == null || document.revision > current.revision) {
        latestById[document.id] = document;
      }
    }
    _latestRecipes = latestById.values.toList(growable: false)
      ..sort((a, b) => a.title.compareTo(b.title));
    _rebuildActiveRecipes();
  }

  void _rebuildActiveRecipes() {
    _activeRecipes =
        _latestRecipes
            .map((latest) {
              final selectedRevision = _activeRevisionsByRecipeId[latest.id];
              return selectedRevision == null
                  ? latest
                  : revisionFor(latest.id, selectedRevision) ?? latest;
            })
            .toList(growable: false)
          ..sort((a, b) => a.title.compareTo(b.title));
    _rebuildSearch();
    _refreshVersionStateLoadError();
  }

  void _refreshVersionStateLoadError() {
    if (!_versionStateReadable) return;
    final hasMissingRevision = _activeRevisionsByRecipeId.entries.any(
      (entry) => revisionFor(entry.key, entry.value) == null,
    );
    _versionStateLoadError = hasMissingRevision
        ? '保存したactive Versionが見つからないレシピは、最新Versionを表示しています。状態は変更していません。'
        : null;
  }

  void _rebuildSearch() {
    final normalizedQuery = normalizeSearchText(_searchQuery);
    if (normalizedQuery.isEmpty) {
      _visibleRecipes = List.unmodifiable(_activeRecipes);
      _searchSuggestions = const [];
      return;
    }

    _visibleRecipes = List.unmodifiable(
      _activeRecipes.where((recipe) {
        return _searchableValues(
          recipe,
        ).any((value) => normalizeSearchText(value).contains(normalizedQuery));
      }),
    );

    final suggestionsByValue = <String, RecipeSearchSuggestion>{};
    for (final recipe in _activeRecipes) {
      _addSuggestion(
        suggestionsByValue,
        recipe.title,
        RecipeSearchSuggestionKind.recipeTitle,
        normalizedQuery,
      );
      for (final ingredient in recipe.ingredients) {
        _addSuggestion(
          suggestionsByValue,
          ingredient.name,
          RecipeSearchSuggestionKind.ingredient,
          normalizedQuery,
        );
      }
      for (final tag in tagsFor(recipe.id)) {
        _addSuggestion(
          suggestionsByValue,
          tag,
          RecipeSearchSuggestionKind.tag,
          normalizedQuery,
        );
      }
    }
    _searchSuggestions = List.unmodifiable(suggestionsByValue.values.take(8));
  }

  Iterable<String> _searchableValues(RecipeDocument recipe) sync* {
    yield recipe.title;
    yield* recipe.ingredients.map((ingredient) => ingredient.name);
    yield* tagsFor(recipe.id);
  }

  void _addSuggestion(
    Map<String, RecipeSearchSuggestion> suggestions,
    String label,
    RecipeSearchSuggestionKind kind,
    String normalizedQuery,
  ) {
    final normalizedLabel = normalizeSearchText(label);
    if (!normalizedLabel.contains(normalizedQuery)) {
      return;
    }
    suggestions.putIfAbsent(
      normalizedLabel,
      () => RecipeSearchSuggestion(label: label, kind: kind),
    );
  }
}

class _RecipeSaveOutcome {
  const _RecipeSaveOutcome(this.document, this.storeResult);

  final RecipeDocument document;
  final StoreRecipeResult storeResult;
}
