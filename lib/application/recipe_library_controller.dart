import 'package:flutter/foundation.dart';

import '../data/recipe_document_store.dart';
import '../data/cooking_store.dart';
import '../data/recipe_tag_store.dart';
import '../domain/recipe_document.dart';
import '../domain/search_text.dart';
import '../domain/recipe_validator.dart';

typedef RecipeSourcePicker = Future<String?> Function();

enum RecipeImportStatus { imported, alreadyExists, cancelled, failed }

class RecipeImportResult {
  const RecipeImportResult(this.status, this.message);

  final RecipeImportStatus status;
  final String message;
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
  }) : cookingStore = cookingStore ?? CookingStore();

  final CookingStore cookingStore;

  RecipeDocument? revisionFor(String id, int revision) {
    for (final document in _documents) {
      if (document.id == id && document.revision == revision) return document;
    }
    return null;
  }

  final RecipeDocumentStore _store;
  final RecipeTagStore _tagStore;
  final RecipeValidator _validator;
  final RecipeSourcePicker _pickRecipeSource;

  List<RecipeDocument> _documents = const [];
  List<RecipeDocument> _latestRecipes = const [];
  List<RecipeDocument> _visibleRecipes = const [];
  Map<String, List<String>> _tagsByRecipeId = const {};
  List<RecipeSearchSuggestion> _searchSuggestions = const [];
  String _searchQuery = '';
  bool _isImporting = false;
  String? _loadError;

  List<RecipeDocument> get recipes => _visibleRecipes;
  int get totalRecipeCount => _latestRecipes.length;
  String get searchQuery => _searchQuery;
  List<RecipeSearchSuggestion> get searchSuggestions => _searchSuggestions;
  bool get isImporting => _isImporting;
  String? get loadError => _loadError;

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
    } catch (error) {
      _documents = const [];
      _latestRecipes = const [];
      _visibleRecipes = const [];
      _tagsByRecipeId = const {};
      _searchSuggestions = const [];
      _loadError = error is RecipeStorageException
          ? error.message
          : '保存済みレシピを読み込めませんでした。';
      notifyListeners();
      return;
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

  void setSearchQuery(String query) {
    if (_searchQuery == query) {
      return;
    }
    _searchQuery = query;
    _rebuildSearch();
    notifyListeners();
  }

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
    _rebuildSearch();
  }

  void _rebuildSearch() {
    final normalizedQuery = normalizeSearchText(_searchQuery);
    if (normalizedQuery.isEmpty) {
      _visibleRecipes = List.unmodifiable(_latestRecipes);
      _searchSuggestions = const [];
      return;
    }

    _visibleRecipes = List.unmodifiable(
      _latestRecipes.where((recipe) {
        return _searchableValues(
          recipe,
        ).any((value) => normalizeSearchText(value).contains(normalizedQuery));
      }),
    );

    final suggestionsByValue = <String, RecipeSearchSuggestion>{};
    for (final recipe in _latestRecipes) {
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
