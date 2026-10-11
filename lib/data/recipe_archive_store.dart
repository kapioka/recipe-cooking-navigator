import 'dart:convert';
import 'dart:io';

/// Local library visibility only; never changes a Recipe document or revision.
class RecipeArchiveStore {
  RecipeArchiveStore([this.file]);

  final File? file;
  Set<String> _memory = {};
  Future<void> _pending = Future<void>.value();

  Future<Set<String>> load() async {
    await _pending;
    return _read();
  }

  Future<Set<String>> _read() async {
    if (file == null) return Set.of(_memory);
    final source = await file!.exists()
        ? file
        : await File('${file!.path}.bak').exists()
        ? File('${file!.path}.bak')
        : null;
    if (source == null) return {};
    try {
      final value = jsonDecode(await source.readAsString());
      if (value is! Map<String, dynamic> ||
          value.length != 2 ||
          value['storage_version'] != 1 ||
          value['archived_recipe_ids'] is! List) {
        throw const FormatException('Invalid archive state.');
      }
      final ids = value['archived_recipe_ids'] as List<dynamic>;
      if (ids.any((id) => id is! String || id.isEmpty) ||
          ids.toSet().length != ids.length) {
        throw const FormatException('Invalid archive ids.');
      }
      return Set<String>.from(ids);
    } catch (error) {
      throw FormatException('アーカイブの保存状態を読み込めません。変更していません。', error);
    }
  }

  Future<void> setArchived(String recipeId, bool archived) {
    if (recipeId.isEmpty) {
      return Future.error(const FormatException('Recipe ID is empty.'));
    }
    final operation = _pending.then((_) async {
      final ids = await _read();
      if (archived) {
        ids.add(recipeId);
      } else {
        ids.remove(recipeId);
      }
      if (file == null) {
        _memory = ids;
        return;
      }
      final temporary = File('${file!.path}.tmp');
      final backup = File('${file!.path}.bak');
      await file!.parent.create(recursive: true);
      if (await temporary.exists()) await temporary.delete();
      await temporary.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'storage_version': 1,
          'archived_recipe_ids': ids.toList()..sort(),
        }),
        flush: true,
      );
      if (await file!.exists()) {
        if (await backup.exists()) await backup.delete();
        await file!.rename(backup.path);
      }
      try {
        await temporary.rename(file!.path);
      } catch (_) {
        if (!await file!.exists() && await backup.exists()) {
          await backup.rename(file!.path);
        }
        rethrow;
      }
      try {
        if (await backup.exists()) await backup.delete();
      } on FileSystemException {
        // The primary state is committed; cleanup may be retried later.
      }
    });
    _pending = operation.catchError((Object _) {});
    return operation;
  }
}
