import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';

enum StoreRecipeResult { added, alreadyExists, conflictingRevision }

abstract interface class RecipeDocumentStore {
  Future<List<Map<String, dynamic>>> loadDocuments();

  Future<StoreRecipeResult> saveDocument(Map<String, dynamic> document);
}

abstract interface class RecipeDocumentDeletionStore {
  Future<void> deleteRecipe(String recipeId);
}

class RecipeStorageException implements Exception {
  const RecipeStorageException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class FileRecipeDocumentStore
    implements RecipeDocumentStore, RecipeDocumentDeletionStore {
  FileRecipeDocumentStore(this.file);

  static const storageVersion = 2;

  final File file;

  File get _backupFile => File('${file.path}.bak');
  File get _temporaryFile => File('${file.path}.tmp');

  @override
  Future<List<Map<String, dynamic>>> loadDocuments() async {
    final source = await _readableSource();
    if (source == null) {
      return [];
    }

    try {
      final decoded = jsonDecode(await source.readAsString());
      if (decoded is! Map<String, dynamic> ||
          decoded['storage_version'] != storageVersion ||
          decoded['recipes'] is! List<dynamic>) {
        throw const FormatException('Unsupported recipe storage structure.');
      }

      return (decoded['recipes'] as List<dynamic>).map((item) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('Recipe entry is not an object.');
        }
        return item;
      }).toList();
    } catch (error) {
      throw RecipeStorageException(
        '保存済みレシピを安全に読み込めませんでした。データは変更していません。',
        error,
      );
    }
  }

  @override
  Future<StoreRecipeResult> saveDocument(Map<String, dynamic> document) async {
    final documents = await loadDocuments();
    final recipe = document['recipe'] as Map<String, dynamic>;
    final id = recipe['id'];
    final revision = recipe['revision'];

    for (final existing in documents) {
      final existingRecipe = existing['recipe'];
      if (existingRecipe is Map<String, dynamic> &&
          existingRecipe['id'] == id &&
          existingRecipe['revision'] == revision) {
        return const DeepCollectionEquality().equals(existing, document)
            ? StoreRecipeResult.alreadyExists
            : StoreRecipeResult.conflictingRevision;
      }
    }

    documents.add(document);
    await _writeDocuments(documents);
    return StoreRecipeResult.added;
  }

  @override
  Future<void> deleteRecipe(String recipeId) async {
    final documents = await loadDocuments();
    final remaining = documents.where((document) {
      final recipe = document['recipe'];
      return recipe is! Map<String, dynamic> || recipe['id'] != recipeId;
    }).toList();
    if (remaining.length == documents.length) return;
    await _writeDocuments(remaining);
  }

  Future<File?> _readableSource() async {
    if (await file.exists()) {
      return file;
    }
    if (await _backupFile.exists()) {
      return _backupFile;
    }
    return null;
  }

  Future<void> _writeDocuments(List<Map<String, dynamic>> documents) async {
    try {
      await file.parent.create(recursive: true);
      if (await _temporaryFile.exists()) {
        await _temporaryFile.delete();
      }

      final payload = const JsonEncoder.withIndent('  ')
          .convert({'storage_version': storageVersion, 'recipes': documents});
      await _temporaryFile.writeAsString(payload, flush: true);

      if (await file.exists()) {
        if (await _backupFile.exists()) {
          await _backupFile.delete();
        }
        await file.rename(_backupFile.path);
      }

      try {
        await _temporaryFile.rename(file.path);
      } catch (error) {
        if (!await file.exists() && await _backupFile.exists()) {
          await _backupFile.rename(file.path);
        }
        rethrow;
      }

      try {
        if (await _backupFile.exists()) {
          await _backupFile.delete();
        }
      } on FileSystemException {
        // The primary file is committed; do not report a false write failure.
      }
    } catch (error) {
      throw RecipeStorageException('レシピを端末へ保存できませんでした。', error);
    }
  }
}
