import 'dart:convert';
import 'dart:io';

import '../domain/search_text.dart';

abstract interface class RecipeTagStore {
  Future<Map<String, List<String>>> loadTags();

  Future<void> saveTags(String recipeId, List<String> tags);
}

class RecipeTagStorageException implements Exception {
  const RecipeTagStorageException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class FileRecipeTagStore implements RecipeTagStore {
  FileRecipeTagStore(this.file);

  static const storageVersion = 1;

  final File file;

  File get _backupFile => File('${file.path}.bak');
  File get _temporaryFile => File('${file.path}.tmp');

  @override
  Future<Map<String, List<String>>> loadTags() async {
    final source = await _readableSource();
    if (source == null) {
      return {};
    }

    try {
      final decoded = jsonDecode(await source.readAsString());
      if (decoded is! Map<String, dynamic> ||
          decoded['storage_version'] != storageVersion ||
          decoded['recipe_tags'] is! List<dynamic>) {
        throw const FormatException('Unsupported recipe tag storage.');
      }

      final result = <String, List<String>>{};
      for (final entry in decoded['recipe_tags'] as List<dynamic>) {
        if (entry is! Map<String, dynamic> ||
            entry['recipe_id'] is! String ||
            entry['tags'] is! List<dynamic>) {
          throw const FormatException('Invalid recipe tag entry.');
        }

        final recipeId = entry['recipe_id'] as String;
        final values = entry['tags'] as List<dynamic>;
        if (recipeId.isEmpty ||
            values.length > 5 ||
            values.any((e) => e is! String) ||
            result.containsKey(recipeId)) {
          throw const FormatException('Invalid recipe tag values.');
        }

        final tags = values.cast<String>();
        final normalized = tags.map(normalizeSearchText).toList();
        if (normalized.any((tag) => tag.isEmpty) ||
            normalized.toSet().length != normalized.length) {
          throw const FormatException('Invalid or duplicate recipe tags.');
        }
        result[recipeId] = List.unmodifiable(tags);
      }
      return result;
    } catch (error) {
      throw RecipeTagStorageException(
        '保存済みタグを安全に読み込めませんでした。レシピは変更していません。',
        error,
      );
    }
  }

  @override
  Future<void> saveTags(String recipeId, List<String> tags) async {
    _validateTags(recipeId, tags);
    final allTags = await loadTags();
    if (tags.isEmpty) {
      allTags.remove(recipeId);
    } else {
      allTags[recipeId] = List.unmodifiable(tags);
    }
    await _writeTags(allTags);
  }

  void _validateTags(String recipeId, List<String> tags) {
    final normalized = tags.map(normalizeSearchText).toList(growable: false);
    if (recipeId.isEmpty ||
        tags.length > 5 ||
        normalized.any((tag) => tag.isEmpty) ||
        normalized.toSet().length != normalized.length) {
      throw const RecipeTagStorageException('タグは空欄と重複を除き、5個まで保存できます。');
    }
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

  Future<void> _writeTags(Map<String, List<String>> allTags) async {
    try {
      await file.parent.create(recursive: true);
      if (await _temporaryFile.exists()) {
        await _temporaryFile.delete();
      }

      final entries =
          allTags.entries
              .map((entry) => {'recipe_id': entry.key, 'tags': entry.value})
              .toList(growable: false)
            ..sort(
              (a, b) => (a['recipe_id']! as String).compareTo(
                b['recipe_id']! as String,
              ),
            );
      final payload = const JsonEncoder.withIndent('  ')
          .convert({'storage_version': storageVersion, 'recipe_tags': entries});
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

      if (await _backupFile.exists()) {
        await _backupFile.delete();
      }
    } catch (error) {
      throw RecipeTagStorageException('タグを端末へ保存できませんでした。', error);
    }
  }
}
