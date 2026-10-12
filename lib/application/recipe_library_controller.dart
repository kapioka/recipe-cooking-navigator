import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';

import '../data/cooking_store.dart';
import '../data/recipe_archive_store.dart';
import '../data/preparation_checklist_store.dart';
import '../data/recipe_document_store.dart';
import '../data/recipe_inbox_state_store.dart';
import '../data/recipe_tag_store.dart';
import '../data/recipe_photo_store.dart';
import '../data/recipe_version_state_store.dart';
import '../domain/recipe_document.dart';
import '../domain/recipe_inbox.dart';
import '../domain/recipe_validator.dart';
import '../domain/search_text.dart';

typedef RecipeSourcePicker = Future<String?> Function();

enum RecipeImportStatus { imported, alreadyExists, cancelled, failed }

enum RecipeImportPreparationStatus { ready, cancelled, failed }

class RecipeImportPreview {
  const RecipeImportPreview._(this._document);

  final RecipeDocument _document;
  String get source => jsonEncode(_document.raw);
  List<String> get notices => [
    _document.servingAdjustmentNote,
    for (final key in ['storage_note', 'lunchbox_note'])
      if (_document.recipeData[key] is List)
        _document
            .renderText(
              _document.recipeData[key] as List,
              _document.contextFor(servings),
            )
            .displayText,
  ];

  String get title => _document.title;
  String get recipeId => _document.id;
  int get revision => _document.revision;
  int? get parentRevision => _document.parentRevision;
  int get servings => _document.servings;
  int get totalTimeMinutes => _document.totalTimeMinutes;
  int get ingredientCount => _document.ingredients.length;
  int get stepCount => _document.steps.length;
  List<String> get ingredientDetails => [
    for (final amount in _document.amounts)
      _document.amountLine(amount.id, _document.contextFor(servings)),
  ];
  List<String> get stepDetails => [
    for (final step in _document.steps)
      '${step['title']}: ${_document.renderText(step['instruction'] as List, _document.contextFor(servings)).displayText}'
          '${step['heat'] is List ? '\n火加減: ${_document.renderText(step['heat'] as List, _document.contextFor(servings)).displayText}' : ''}'
          '${step['done_when'] is List ? '\n完了の目安: ${_document.renderText(step['done_when'] as List, _document.contextFor(servings)).displayText}' : ''}',
  ];
}

class RecipeImportPreparation {
  const RecipeImportPreparation({
    required this.status,
    required this.message,
    this.preview,
    this.errorCode,
  });

  final RecipeImportPreparationStatus status;
  final String message;
  final RecipeImportPreview? preview;
  final RecipeImportErrorCode? errorCode;
}

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
    PreparationChecklistStore? preparationStore,
    RecipeInboxPlatform? recipeInboxPlatform,
    RecipeInboxStateStore? recipeInboxStateStore,
    RecipeVersionStateStore? recipeVersionStateStore,
    RecipeArchiveStore? archiveStore,
    RecipePhotoStore? photoStore,
    this.legacyDataPresent = false,
  }) : assert(
         (recipeInboxPlatform == null) == (recipeInboxStateStore == null),
         'Inbox platform and state store must be provided together.',
       ),
       cookingStore = cookingStore ?? CookingStore(),
       preparationStore = preparationStore ?? PreparationChecklistStore(),
       _recipeInboxPlatform = recipeInboxPlatform,
       _recipeInboxStateStore = recipeInboxStateStore,
       _recipeVersionStateStore =
           recipeVersionStateStore ?? MemoryRecipeVersionStateStore(),
       _archiveStore = archiveStore ?? RecipeArchiveStore(),
       _photoStore = photoStore ?? MemoryRecipePhotoStore();

  final CookingStore cookingStore;
  final PreparationChecklistStore preparationStore;
  final bool legacyDataPresent;

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
  final RecipeArchiveStore _archiveStore;
  final RecipePhotoStore _photoStore;
  final _photos = <String, Uint8List>{};
  final _photoErrors = <String, String>{};
  final _photoWrites = <String>{};

  Uint8List? photoFor(String recipeId) => _photos[recipeId];
  String? photoErrorFor(String recipeId) => _photoErrors[recipeId];
  bool isSavingPhoto(String recipeId) => _photoWrites.contains(recipeId);

  Future<String?> setRecipePhoto(String recipeId, Uint8List? png) async {
    if (!_photoWrites.add(recipeId)) return '写真を保存しています。';
    notifyListeners();
    try {
      return await _synchronizeLibraryMutation(() async {
        if (latestRecipeFor(recipeId) == null) return 'レシピが見つかりません。';
        try {
          await _photoStore.save(recipeId, png);
          if (png == null) {
            _photos.remove(recipeId);
          } else {
            _photos[recipeId] = Uint8List.fromList(png).asUnmodifiableView();
          }
          _photoErrors.remove(recipeId);
          return null;
        } catch (_) {
          return '写真を保存できませんでした。元の写真は変更していません。';
        }
      });
    } finally {
      _photoWrites.remove(recipeId);
      notifyListeners();
    }
  }

  List<RecipeDocument> _documents = const [];
  List<RecipeDocument> _latestRecipes = const [];
  List<RecipeDocument> _activeRecipes = const [];
  List<RecipeDocument> _archivedRecipes = const [];
  Set<String> _archivedIds = const {};
  String? _archiveLoadError;
  bool _archiveReadable = true;
  List<RecipeDocument> _visibleRecipes = const [];
  Map<String, int> _activeRevisionsByRecipeId = const {};
  Map<String, List<String>> _tagsByRecipeId = const {};
  List<RecipeSearchSuggestion> _searchSuggestions = const [];
  String _searchQuery = '';
  bool _isImporting = false;
  RecipeImportPreview? _pendingFileImport;
  bool _isCheckingInbox = false;
  bool _isSelectingInboxFolder = false;
  Future<RecipeInboxRunResult>? _activeInboxCheck;
  Future<void> _libraryMutationTail = Future<void>.value();
  RecipeInboxFolder? _inboxFolder;
  String? _loadError;
  String? _versionStateLoadError;
  bool _versionStateReadable = true;

  List<RecipeDocument> get recipes => _visibleRecipes;
  List<RecipeDocument> get archivedRecipes =>
      List.unmodifiable(_archivedRecipes);
  int get totalRecipeCount => _activeRecipes.length;
  String get searchQuery => _searchQuery;
  List<RecipeSearchSuggestion> get searchSuggestions => _searchSuggestions;
  bool get isImporting => _isImporting;
  bool _creationOpen = false;
  bool get creationOpen => _creationOpen;
  void setCreationOpen(bool value) {
    _creationOpen = value;
    notifyListeners();
  }

  bool get isCheckingInbox => _isCheckingInbox;
  bool get isSelectingInboxFolder => _isSelectingInboxFolder;
  bool get isInboxBusy => _isCheckingInbox || _isSelectingInboxFolder;
  bool get isBusy => _isImporting || isInboxBusy;
  RecipeInboxFolder? get inboxFolder => _inboxFolder;
  String? get loadError {
    final messages = <String>[
      ?_loadError,
      ?_versionStateLoadError,
      ?_archiveLoadError,
    ];
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
      _archivedRecipes = const [];
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

    try {
      _archivedIds = await _archiveStore.load();
      _archiveReadable = true;
      _archiveLoadError = null;
      _rebuildActiveRecipes();
    } catch (_) {
      _archiveReadable = false;
      _archiveLoadError = 'アーカイブを読み込めませんでした。アーカイブ操作と完全削除は停止しています。';
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
    _photos.clear();
    _photoErrors.clear();
    for (final id in _documents.map((doc) => doc.id).toSet()) {
      try {
        final photo = await _photoStore.read(id);
        if (photo != null) _photos[id] = photo.asUnmodifiableView();
      } catch (_) {
        _photoErrors[id] = '写真を読み込めません。タップして変更または削除できます。';
      }
    }
    notifyListeners();
  }

  Future<RecipeImportResult> importFromFile() async {
    final preparation = await prepareImportFromFile();
    return switch (preparation.status) {
      RecipeImportPreparationStatus.ready => confirmPreparedImport(
        preparation.preview!,
      ),
      RecipeImportPreparationStatus.cancelled => RecipeImportResult(
        RecipeImportStatus.cancelled,
        preparation.message,
      ),
      RecipeImportPreparationStatus.failed => RecipeImportResult(
        RecipeImportStatus.failed,
        preparation.message,
      ),
    };
  }

  Future<RecipeImportPreparation> prepareImportFromFile() async {
    final busy = _beginPreparedImport();
    if (busy != null) return busy;

    try {
      final source = await _pickRecipeSource();
      if (source == null) {
        _finishPreparedImport();
        return const RecipeImportPreparation(
          status: RecipeImportPreparationStatus.cancelled,
          message: '取り込みをキャンセルしました。',
        );
      }
      return _prepareImportSource(source);
    } on RecipeImportException catch (error) {
      _finishPreparedImport();
      return RecipeImportPreparation(
        status: RecipeImportPreparationStatus.failed,
        message: error.message,
      );
    } on RecipeStorageException catch (error) {
      _finishPreparedImport();
      return RecipeImportPreparation(
        status: RecipeImportPreparationStatus.failed,
        message: error.message,
      );
    } catch (_) {
      _finishPreparedImport();
      return const RecipeImportPreparation(
        status: RecipeImportPreparationStatus.failed,
        message: 'ファイルを読み込めませんでした。もう一度お試しください。',
      );
    }
  }

  Future<RecipeImportPreparation> prepareImportSource(
    String source, {
    RecipeImportPreview? replacing,
    bool Function(RecipeImportPreview)? accepts,
  }) async {
    // Validate before replacing the single owned slot. Failed regeneration must
    // leave the previous candidate intact.
    if (replacing != null && identical(replacing, _pendingFileImport)) {
      try {
        final preview = RecipeImportPreview._(
          _validator.validateSource(source),
        );
        if (accepts != null && !accepts(preview)) {
          return const RecipeImportPreparation(
            status: RecipeImportPreparationStatus.failed,
            message: '生成したレシピのID・版・改善元が依頼と一致しません。保存していません。',
          );
        }
        _pendingFileImport = preview;
        return RecipeImportPreparation(
          status: RecipeImportPreparationStatus.ready,
          message: '内容を確認してください。',
          preview: preview,
        );
      } on RecipeImportException catch (error) {
        return RecipeImportPreparation(
          status: RecipeImportPreparationStatus.failed,
          message: error.message,
          errorCode: error.code,
        );
      }
    }
    final busy = _beginPreparedImport();
    if (busy != null) return busy;
    try {
      final prepared = _prepareImportSource(source);
      if (accepts != null && !accepts(prepared.preview!)) {
        _finishPreparedImport();
        return const RecipeImportPreparation(
          status: RecipeImportPreparationStatus.failed,
          message: '生成したレシピのID・版・改善元が依頼と一致しません。保存していません。',
        );
      }
      return prepared;
    } on RecipeImportException catch (error) {
      _finishPreparedImport();
      return RecipeImportPreparation(
        status: RecipeImportPreparationStatus.failed,
        message: error.message,
        errorCode: error.code,
      );
    } catch (_) {
      _finishPreparedImport();
      return const RecipeImportPreparation(
        status: RecipeImportPreparationStatus.failed,
        message: '共有されたレシピを読み込めませんでした。',
      );
    }
  }

  /// Revalidate the retained immutable candidate after a failed save. A different
  /// owner's pending import cannot be replaced by retry.
  Future<RecipeImportPreparation> reprepareImport(
    RecipeImportPreview preview,
  ) => prepareImportSource(preview.source, replacing: preview);

  bool isStoredPreview(RecipeImportPreview preview) {
    final saved = revisionFor(preview.recipeId, preview.revision);
    return saved != null &&
        const DeepCollectionEquality().equals(saved.raw, preview._document.raw);
  }

  RecipeImportPreparation? _beginPreparedImport() {
    if (_isImporting) {
      return const RecipeImportPreparation(
        status: RecipeImportPreparationStatus.failed,
        message: '別のレシピを確認中です。完了してからもう一度お試しください。',
      );
    }
    _isImporting = true;
    notifyListeners();
    return null;
  }

  RecipeImportPreparation _prepareImportSource(String source) {
    final preview = RecipeImportPreview._(_validator.validateSource(source));
    _pendingFileImport = preview;
    return RecipeImportPreparation(
      status: RecipeImportPreparationStatus.ready,
      message: '取り込むレシピを確認してください。',
      preview: preview,
    );
  }

  Future<RecipeImportResult> confirmPreparedImport(
    RecipeImportPreview preview, {
    bool preserveActive = false,
  }) async {
    if (!identical(preview, _pendingFileImport)) {
      return const RecipeImportResult(
        RecipeImportStatus.failed,
        '確認中のレシピが変わったため、取り込みませんでした。',
      );
    }
    try {
      return _resultFor(
        await _saveDocument(preview._document, preserveActive: preserveActive),
      );
    } on RecipeStorageException catch (error) {
      return RecipeImportResult(RecipeImportStatus.failed, error.message);
    } catch (_) {
      return const RecipeImportResult(
        RecipeImportStatus.failed,
        'レシピを保存できませんでした。保存済みデータは変更していません。',
      );
    } finally {
      if (identical(preview, _pendingFileImport)) _finishPreparedImport();
    }
  }

  void cancelPreparedImport(RecipeImportPreview preview) {
    if (identical(preview, _pendingFileImport)) _finishPreparedImport();
  }

  void _finishPreparedImport() {
    _pendingFileImport = null;
    _isImporting = false;
    notifyListeners();
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
    return _resultFor(outcome);
  }

  RecipeImportResult _resultFor(_RecipeSaveOutcome outcome) {
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
      _saveDocument(_validator.validateSource(source));

  Future<_RecipeSaveOutcome> _saveDocument(
    RecipeDocument document, {
    bool preserveActive = false,
  }) => _synchronizeLibraryMutation(() async {
    // AI revision approval must not move an implicit latest-as-active choice.
    // Persist the current choice before adding a revision; failure stops save.
    final currentActive = activeRecipeFor(document.id);
    if (preserveActive &&
        currentActive != null &&
        !_activeRevisionsByRecipeId.containsKey(document.id)) {
      await _recipeVersionStateStore.saveActiveRevision(
        document.id,
        currentActive.revision,
      );
      _activeRevisionsByRecipeId = Map.unmodifiable({
        ..._activeRevisionsByRecipeId,
        document.id: currentActive.revision,
      });
    }
    final storeResult = await _store.saveDocument(document.raw);
    if (storeResult == StoreRecipeResult.added ||
        (storeResult == StoreRecipeResult.alreadyExists &&
            revisionFor(document.id, document.revision) == null)) {
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
  ) => _synchronizeLibraryMutation(() async {
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
  });

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
    final allRecipes = _latestRecipes
        .map((latest) {
          final selectedRevision = _activeRevisionsByRecipeId[latest.id];
          return selectedRevision == null
              ? latest
              : revisionFor(latest.id, selectedRevision) ?? latest;
        })
        .toList(growable: false);
    _activeRecipes =
        allRecipes.where((r) => !_archivedIds.contains(r.id)).toList()
          ..sort((a, b) => a.title.compareTo(b.title));
    _archivedRecipes =
        allRecipes.where((r) => _archivedIds.contains(r.id)).toList()
          ..sort((a, b) => a.title.compareTo(b.title));
    _rebuildSearch();
    _refreshVersionStateLoadError();
  }

  Future<String> setArchived(String recipeId, bool archived) =>
      _synchronizeLibraryMutation(() async {
        if (!_archiveReadable) return 'アーカイブを読み込めないため、変更していません。';
        if (latestRecipeFor(recipeId) == null) return 'レシピが見つかりません。';
        try {
          await _archiveStore.setArchived(recipeId, archived);
          final updated = Set<String>.of(_archivedIds);
          if (archived) {
            updated.add(recipeId);
          } else {
            updated.remove(recipeId);
          }
          _archivedIds = updated;
          _rebuildActiveRecipes();
          notifyListeners();
          return archived ? 'レシピをアーカイブへ移しました。' : 'レシピを一覧へ戻しました。';
        } catch (_) {
          return 'アーカイブを保存できませんでした。変更していません。';
        }
      });

  Future<String> deleteArchivedRecipe(String recipeId) =>
      _synchronizeLibraryMutation(() async {
        if (!_archiveReadable || !_archivedIds.contains(recipeId)) {
          return 'アーカイブ内のレシピだけを完全削除できます。';
        }
        final documentStore = _store;
        final versionStore = _recipeVersionStateStore;
        if (documentStore is! RecipeDocumentDeletionStore ||
            versionStore is! RecipeVersionStateDeletionStore) {
          return 'この保存先では完全削除を利用できません。';
        }
        try {
          // Read every affected store before the first destructive write.
          for (final raw in await _store.loadDocuments()) {
            _validator.validateDocument(raw);
          }
          await _tagStore.loadTags();
          await _recipeVersionStateStore.loadActiveRevisions();
          await cookingStore.read();
          for (final revision in revisionsFor(recipeId)) {
            await preparationStore.checked(recipeId, revision.revision);
          }
          await _archiveStore.load();
        } catch (_) {
          return '関連データを読み込めないため、削除していません。';
        }
        try {
          // Keep the Recipe and archive marker until the dependent stores
          // have been cleared, so an interrupted deletion remains retryable.
          await cookingStore.deleteRecipe(recipeId);
          await preparationStore.deleteRecipe(recipeId);
          await _tagStore.saveTags(recipeId, const []);
          await _photoStore.save(recipeId, null);
          await (versionStore as RecipeVersionStateDeletionStore).deleteRecipe(
            recipeId,
          );
          await (documentStore as RecipeDocumentDeletionStore).deleteRecipe(
            recipeId,
          );
          _documents = _documents.where((d) => d.id != recipeId).toList();
          _activeRevisionsByRecipeId = {..._activeRevisionsByRecipeId}
            ..remove(recipeId);
          _tagsByRecipeId = {..._tagsByRecipeId}..remove(recipeId);
          _photos.remove(recipeId);
          _photoErrors.remove(recipeId);
          _rebuildLatestRecipes();
          notifyListeners();
        } catch (_) {
          return '完全削除を完了できませんでした。レシピはアーカイブに残しています。再試行してください。';
        }
        try {
          await _archiveStore.setArchived(recipeId, false);
          _archivedIds = Set.of(_archivedIds)..remove(recipeId);
          return 'レシピと関連する端末内データを完全削除しました。';
        } catch (_) {
          return 'レシピ本体は削除しましたが、アーカイブ記録の整理に失敗しました。次回の取込前に再確認してください。';
        }
      });

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
