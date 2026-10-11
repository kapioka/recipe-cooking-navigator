import 'dart:convert';
import 'dart:io';

/// Local checklist state. Recipe documents and CookingContext stay immutable.
class PreparationChecklistStore {
  PreparationChecklistStore([this.file]);

  final File? file;
  Map<String, dynamic> _memory = _empty();
  Future<void> _pending = Future.value();

  static Map<String, dynamic> _empty() => {
    'storage_version': 1,
    'recipes': <String, dynamic>{},
  };

  Future<Set<String>> checked(String recipeId, int revision) async {
    await _pending;
    final data = await _read();
    final revisions =
        (data['recipes'] as Map<String, dynamic>)[recipeId]
            as Map<String, dynamic>?;
    return Set<String>.from((revisions?['$revision'] as List<dynamic>?) ?? []);
  }

  Future<void> setChecked(
    String recipeId,
    int revision,
    String taskId,
    bool checked,
  ) => _update((data) {
    if (recipeId.isEmpty || revision < 1 || taskId.isEmpty) {
      throw const FormatException('事前準備の識別情報が正しくありません。');
    }
    final recipes = data['recipes'] as Map<String, dynamic>;
    final revisions = recipes.putIfAbsent(
      recipeId,
      () => <String, dynamic>{},
    ) as Map<String, dynamic>;
    final ids = Set<String>.from(
      (revisions['$revision'] as List<dynamic>?) ?? const [],
    );
    if (checked) {
      ids.add(taskId);
    } else {
      ids.remove(taskId);
    }
    if (ids.isEmpty) {
      revisions.remove('$revision');
      if (revisions.isEmpty) recipes.remove(recipeId);
    } else {
      revisions['$revision'] = ids.toList()..sort();
    }
  });

  Future<void> reset(String recipeId, int revision) => _update((data) {
    final recipes = data['recipes'] as Map<String, dynamic>;
    final revisions = recipes[recipeId] as Map<String, dynamic>?;
    revisions?.remove('$revision');
    if (revisions?.isEmpty ?? false) recipes.remove(recipeId);
  });

  Future<void> deleteRecipe(String recipeId) => _update((data) {
    (data['recipes'] as Map<String, dynamic>).remove(recipeId);
  });

  Future<Map<String, dynamic>> _read() async {
    if (file == null) return _copy(_memory);
    FormatException? invalid;
    for (final candidate in [
      file!,
      File('${file!.path}.bak'),
      File('${file!.path}.previous'),
    ]) {
      if (!await candidate.exists()) continue;
      try {
        final decoded = jsonDecode(await candidate.readAsString());
        if (decoded is! Map<String, dynamic>) throw const FormatException();
        _validate(decoded);
        return decoded;
      } on FormatException catch (error) {
        invalid = error;
      }
    }
    if (invalid != null) {
      throw const FormatException('事前準備の保存状態を読み込めません。');
    }
    return _empty();
  }

  void _validate(Map<String, dynamic> data) {
    if (data.length != 2 ||
        data['storage_version'] != 1 ||
        data['recipes'] is! Map<String, dynamic>) {
      throw const FormatException('事前準備の保存形式が正しくありません。');
    }
    for (final recipe in (data['recipes'] as Map<String, dynamic>).entries) {
      if (recipe.key.isEmpty || recipe.value is! Map<String, dynamic>) {
        throw const FormatException('事前準備の保存形式が正しくありません。');
      }
      for (final revision in (recipe.value as Map<String, dynamic>).entries) {
        final number = int.tryParse(revision.key);
        if (number == null ||
            number < 1 ||
            '$number' != revision.key ||
            revision.value is! List) {
          throw const FormatException('事前準備の保存形式が正しくありません。');
        }
        final ids = revision.value as List<dynamic>;
        if (ids.any((id) => id is! String || id.isEmpty) ||
            ids.toSet().length != ids.length) {
          throw const FormatException('事前準備の保存形式が正しくありません。');
        }
      }
    }
  }

  Future<void> _update(void Function(Map<String, dynamic>) change) {
    final result = _pending.then((_) async {
      final data = await _read();
      change(data);
      _validate(data);
      if (file == null) {
        _memory = data;
        return;
      }
      final target = file!;
      final temp = File('${target.path}.tmp');
      final backup = File('${target.path}.bak');
      final previous = File('${target.path}.previous');
      await target.parent.create(recursive: true);
      await temp.writeAsString(jsonEncode(data), flush: true);
      if (await target.exists()) {
        if (await previous.exists()) await previous.delete();
        await target.rename(previous.path);
      }
      try {
        await temp.rename(target.path);
      } catch (_) {
        if (!await target.exists() && await previous.exists()) {
          await previous.rename(target.path);
        }
        rethrow;
      }
      try {
        await target.copy(backup.path);
        if (await previous.exists()) await previous.delete();
      } on FileSystemException {
        // Primary is committed; retain a recovery file if cleanup fails.
      }
    });
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  static Map<String, dynamic> _copy(Map<String, dynamic> value) =>
      jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
}
