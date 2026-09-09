import 'dart:async';
import 'dart:convert';
import 'dart:io';

abstract interface class RecipeVersionStateStore {
  Future<Map<String, int>> loadActiveRevisions();

  Future<void> saveActiveRevision(String recipeId, int revision);
}

class RecipeVersionStateStorageException implements Exception {
  const RecipeVersionStateStorageException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class MemoryRecipeVersionStateStore implements RecipeVersionStateStore {
  MemoryRecipeVersionStateStore([Map<String, int>? initial])
    : _activeRevisions = Map<String, int>.from(initial ?? const {});

  final Map<String, int> _activeRevisions;

  @override
  Future<Map<String, int>> loadActiveRevisions() async =>
      Map.unmodifiable(_activeRevisions);

  @override
  Future<void> saveActiveRevision(String recipeId, int revision) async {
    _validateEntry(recipeId, revision);
    _activeRevisions[recipeId] = revision;
  }
}

class FileRecipeVersionStateStore implements RecipeVersionStateStore {
  FileRecipeVersionStateStore(this.file);

  static const storageVersion = 1;

  final File file;
  Future<void> _operationTail = Future<void>.value();

  File get _backupFile => File('${file.path}.bak');
  File get _temporaryFile => File('${file.path}.tmp');

  @override
  Future<Map<String, int>> loadActiveRevisions() =>
      _synchronize(_readActiveRevisions);

  @override
  Future<void> saveActiveRevision(String recipeId, int revision) {
    _validateEntry(recipeId, revision);
    return _synchronize(() async {
      final activeRevisions = await _readActiveRevisions();
      activeRevisions[recipeId] = revision;
      await _writeActiveRevisions(activeRevisions);
    });
  }

  Future<Map<String, int>> _readActiveRevisions() async {
    final source = await _readableSource();
    if (source == null) {
      return {};
    }

    try {
      final decoded = jsonDecode(await source.readAsString());
      if (decoded is! Map<String, dynamic> ||
          decoded['storage_version'] != storageVersion ||
          decoded['active_revisions'] is! Map<String, dynamic>) {
        throw const FormatException(
          'Unsupported recipe version state structure.',
        );
      }

      final activeRevisions = <String, int>{};
      for (final entry
          in (decoded['active_revisions'] as Map<String, dynamic>).entries) {
        if (entry.value is! int) {
          throw const FormatException('Active revision is not an integer.');
        }
        final revision = entry.value as int;
        _validateEntry(entry.key, revision);
        activeRevisions[entry.key] = revision;
      }
      return activeRevisions;
    } catch (error) {
      throw RecipeVersionStateStorageException(
        'active Versionの保存状態を安全に読み込めませんでした。状態は変更していません。',
        error,
      );
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

  Future<void> _writeActiveRevisions(Map<String, int> activeRevisions) async {
    try {
      await file.parent.create(recursive: true);
      if (await _temporaryFile.exists()) {
        await _temporaryFile.delete();
      }

      final payload = const JsonEncoder.withIndent('  ').convert({
        'storage_version': storageVersion,
        'active_revisions': activeRevisions,
      });
      await _temporaryFile.writeAsString(payload, flush: true);

      if (await file.exists()) {
        if (await _backupFile.exists()) {
          await _backupFile.delete();
        }
        await file.rename(_backupFile.path);
      }

      try {
        await _temporaryFile.rename(file.path);
      } catch (_) {
        if (!await file.exists() && await _backupFile.exists()) {
          await _backupFile.rename(file.path);
        }
        rethrow;
      }

      try {
        if (await _backupFile.exists()) {
          await _backupFile.delete();
        }
      } catch (_) {
        // The primary file is already committed. The next write can retry
        // stale-backup cleanup without reporting this commit as failed.
      }
    } catch (error) {
      throw RecipeVersionStateStorageException(
        'active Versionを端末へ保存できませんでした。',
        error,
      );
    }
  }

  Future<T> _synchronize<T>(Future<T> Function() operation) {
    final previous = _operationTail;
    final release = Completer<void>();
    _operationTail = release.future;
    return () async {
      await previous;
      try {
        return await operation();
      } finally {
        release.complete();
      }
    }();
  }
}

void _validateEntry(String recipeId, int revision) {
  if (recipeId.trim().isEmpty || revision < 1) {
    throw const FormatException('Invalid active recipe revision entry.');
  }
}
