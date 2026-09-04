import 'package:flutter/foundation.dart';

import '../data/recipe_document_store.dart';
import '../domain/recipe_document.dart';
import '../domain/recipe_validator.dart';

typedef RecipeSourcePicker = Future<String?> Function();

enum RecipeImportStatus { imported, alreadyExists, cancelled, failed }

class RecipeImportResult {
  const RecipeImportResult(this.status, this.message);

  final RecipeImportStatus status;
  final String message;
}

class RecipeLibraryController extends ChangeNotifier {
  RecipeLibraryController(this._store, this._validator, this._pickRecipeSource);

  final RecipeDocumentStore _store;
  final RecipeValidator _validator;
  final RecipeSourcePicker _pickRecipeSource;

  List<RecipeDocument> _documents = const [];
  List<RecipeDocument> _recipes = const [];
  bool _isImporting = false;
  String? _loadError;

  List<RecipeDocument> get recipes => _recipes;
  bool get isImporting => _isImporting;
  String? get loadError => _loadError;

  Future<void> load() async {
    try {
      final stored = await _store.loadDocuments();
      _documents = stored
          .map(_validator.validateDocument)
          .toList(growable: false);
      _rebuildLatestRecipes();
      _loadError = null;
    } catch (error) {
      _documents = const [];
      _recipes = const [];
      _loadError = error is RecipeStorageException
          ? error.message
          : '保存済みレシピを読み込めませんでした。';
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

  @visibleForTesting
  Future<RecipeImportResult> importSource(String source) async {
    final document = _validator.validateSource(source);
    final saveResult = await _store.saveDocument(document.raw);

    switch (saveResult) {
      case StoreRecipeResult.added:
        _documents = [..._documents, document];
        _rebuildLatestRecipes();
        notifyListeners();
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

  void _rebuildLatestRecipes() {
    final latestById = <String, RecipeDocument>{};
    for (final document in _documents) {
      final current = latestById[document.id];
      if (current == null || document.revision > current.revision) {
        latestById[document.id] = document;
      }
    }
    _recipes = latestById.values.toList(growable: false)
      ..sort((a, b) => a.title.compareTo(b.title));
  }
}
