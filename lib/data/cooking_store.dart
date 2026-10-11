import 'dart:convert';
import 'dart:io';

import '../domain/cooking_context.dart';
import '../domain/recipe_document.dart';
import '../domain/recipe_validator.dart';
import '../domain/session_assessment.dart';

/// Local UI progress and completed sessions; never modifies Recipe documents.
class CookingStore {
  CookingStore([this.file, this.recipeValidator]);

  final File? file;
  final RecipeValidator? recipeValidator;
  Map<String, dynamic> _memory = _emptyData();
  Future<void> _pending = Future.value();

  static Map<String, dynamic> _emptyData() => {
    'storage_version': 2,
    'help_seen': false,
    'progress': <String, dynamic>{},
    'sessions': <Map<String, dynamic>>[],
  };

  Future<Map<String, dynamic>> read() async {
    await _pending;
    return _readUnlocked();
  }

  Future<Map<String, dynamic>> _readUnlocked() async {
    if (file == null) {
      final copy = _copy(_memory);
      _validateData(copy);
      return copy;
    }
    final backup = File('${file!.path}.bak');
    final interrupted = File('${file!.path}.previous');
    FormatException? invalidData;
    for (final candidate in [file!, backup, interrupted]) {
      if (!await candidate.exists()) continue;
      try {
        return await _readFile(candidate);
      } on FormatException catch (error) {
        invalidData = error;
      }
    }
    if (invalidData != null) throw invalidData;
    return _emptyData();
  }

  Future<Map<String, dynamic>> _readFile(File source) async {
    final dynamic data;
    try {
      data = jsonDecode(await source.readAsString());
    } on FormatException {
      throw const FormatException('調理位置の保存形式を読み込めません。');
    }
    if (data is! Map<String, dynamic>) {
      throw const FormatException('調理位置の保存形式を読み込めません。');
    }
    _validateData(data);
    return data;
  }

  void _validateData(Map<String, dynamic> data) {
    if (data['storage_version'] != 2 ||
        data['help_seen'] is! bool ||
        data['progress'] is! Map<String, dynamic> ||
        data['sessions'] is! List) {
      throw const FormatException('調理位置の保存形式を読み込めません。');
    }
    for (final entry in (data['progress'] as Map<String, dynamic>).entries) {
      final progress = entry.value;
      if (progress is! Map<String, dynamic> ||
          progress['recipe_id'] != entry.key ||
          !_validIdentityAndDates(progress, completed: false)) {
        throw const FormatException('調理位置が破損しています。');
      }
      _validateSnapshotAndContext(progress, requireStep: true);
    }
    for (final rawSession in data['sessions'] as List<dynamic>) {
      if (rawSession is! Map<String, dynamic> ||
          rawSession['session_id'] is! String ||
          (rawSession['session_id'] as String).isEmpty ||
          !_validIdentityAndDates(rawSession, completed: true)) {
        throw const FormatException('調理履歴が破損しています。');
      }
      _validateSnapshotAndContext(rawSession, requireStep: false);
      if (rawSession['assessment'] case final Map<String, dynamic> assessment) {
        SessionAssessment.fromJson(assessment);
      } else if (rawSession.containsKey('assessment')) {
        throw const FormatException('調理後の評価が破損しています。');
      }
    }
  }

  bool _validIdentityAndDates(
    Map<String, dynamic> value, {
    required bool completed,
  }) {
    if (value['recipe_id'] is! String ||
        (value['recipe_id'] as String).isEmpty ||
        value['revision'] is! int ||
        (value['revision'] as int) < 1 ||
        value['started_at'] is! String ||
        DateTime.tryParse(value['started_at'] as String) == null) {
      return false;
    }
    if (completed) {
      return value['completed_at'] is String &&
          DateTime.tryParse(value['completed_at'] as String) != null;
    }
    return value['step_id'] is String &&
        (value['step_id'] as String).isNotEmpty &&
        value['updated_at'] is String &&
        DateTime.tryParse(value['updated_at'] as String) != null;
  }

  void _validateSnapshotAndContext(
    Map<String, dynamic> value, {
    required bool requireStep,
  }) {
    final snapshot = value['recipe_snapshot'];
    final rawContext = value['cooking_context'];
    if (snapshot is! Map<String, dynamic> ||
        rawContext is! Map<String, dynamic>) {
      throw const FormatException('調理条件が破損しています。');
    }
    final recipe =
        recipeValidator?.validateDocument(snapshot) ??
        RecipeDocument.fromValidatedJson(snapshot);
    if (recipe.id != value['recipe_id'] ||
        recipe.revision != value['revision']) {
      throw const FormatException('保存したRecipeの識別情報が一致しません。');
    }
    final context = CookingContext.fromJson(rawContext);
    recipe.validateContext(context);
    if (requireStep &&
        recipe.steps.every((step) => step['id'] != value['step_id'])) {
      throw const FormatException('保存した工程がRecipeにありません。');
    }
  }

  Future<void> startCooking(
    RecipeDocument recipe,
    CookingContext context,
    String stepId,
  ) {
    if (stepId.isEmpty || recipe.steps.every((step) => step['id'] != stepId)) {
      return Future.error(const FormatException('保存する調理位置が正しくありません。'));
    }
    try {
      recipe.validateContext(context);
    } on FormatException catch (error) {
      return Future.error(error);
    }
    return _update((data) {
      final now = DateTime.now().toUtc().toIso8601String();
      (data['progress'] as Map<String, dynamic>)[recipe.id] = {
        'recipe_id': recipe.id,
        'revision': recipe.revision,
        'step_id': stepId,
        'started_at': now,
        'updated_at': now,
        'recipe_snapshot': RecipeDocument.copyJson(recipe.raw),
        'cooking_context': context.toJson(),
      };
    });
  }

  Future<void> updatePosition(String id, int revision, String stepId) {
    if (id.isEmpty || revision < 1 || stepId.isEmpty) {
      return Future.error(const FormatException('保存する調理位置が正しくありません。'));
    }
    return _update((data) {
      final progress = data['progress'] as Map<String, dynamic>;
      final previous = progress[id] as Map<String, dynamic>?;
      if (previous == null || previous['revision'] != revision) {
        throw const FormatException('調理条件を確認できないため位置を保存できません。');
      }
      final snapshot = Map<String, dynamic>.from(
        previous['recipe_snapshot'] as Map,
      );
      final recipe =
          recipeValidator?.validateDocument(snapshot) ??
          RecipeDocument.fromValidatedJson(snapshot);
      if (recipe.steps.every((step) => step['id'] != stepId)) {
        throw const FormatException('保存する工程がRecipeにありません。');
      }
      progress[id] = {
        ...previous,
        'step_id': stepId,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
    });
  }

  Future<void> complete(String id, int revision) => _update((data) {
    final progress = data['progress'] as Map<String, dynamic>;
    final previous = progress[id] as Map<String, dynamic>?;
    if (previous == null || previous['revision'] != revision) {
      throw const FormatException('調理位置を確認できないため完了を保存できません。');
    }
    (data['sessions'] as List<dynamic>).add({
      'session_id': '${id}_${DateTime.now().microsecondsSinceEpoch}',
      'recipe_id': id,
      'revision': revision,
      'started_at': previous['started_at'],
      'completed_at': DateTime.now().toUtc().toIso8601String(),
      'recipe_snapshot': RecipeDocument.copyJson(
        Map<String, dynamic>.from(previous['recipe_snapshot'] as Map),
      ),
      'cooking_context': _copy(
        Map<String, dynamic>.from(previous['cooking_context'] as Map),
      ),
    });
    progress.remove(id);
  });

  Future<void> saveAssessment(String sessionId, SessionAssessment assessment) {
    assessment.validate();
    return _update((data) {
      final sessions = data['sessions'] as List<dynamic>;
      final matches = sessions
          .where(
            (session) =>
                (session as Map<String, dynamic>)['session_id'] == sessionId,
          )
          .toList();
      if (matches.length != 1) {
        throw const FormatException('評価対象の調理記録が見つかりません。');
      }
      (matches.single as Map<String, dynamic>)['assessment'] = assessment
          .toJson();
    });
  }

  Future<void> markHelpSeen() => _update((data) {
    data['help_seen'] = true;
  });

  Future<void> deleteRecipe(String recipeId) => _update((data) {
    (data['progress'] as Map<String, dynamic>).remove(recipeId);
    (data['sessions'] as List<dynamic>).removeWhere(
      (session) =>
          session is Map<String, dynamic> && session['recipe_id'] == recipeId,
    );
  });

  Future<void> _update(void Function(Map<String, dynamic>) change) {
    final previousOperation = _pending;
    final result = previousOperation.then((_) async {
      final data = await _readUnlocked();
      change(data);
      _validateData(data);
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
