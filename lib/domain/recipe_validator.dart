import 'dart:convert';

import 'package:json_schema/json_schema.dart';

import 'recipe_document.dart';

const supportedRecipeSchemaVersion = '2.0.0';

enum RecipeImportErrorCode {
  malformedJson,
  invalidRoot,
  unsupportedSchemaVersion,
  unexpectedDocumentType,
  schemaViolation,
}

class RecipeImportException implements Exception {
  const RecipeImportException(
    this.code,
    this.message, {
    this.details = const [],
  });

  final RecipeImportErrorCode code;
  final String message;
  final List<String> details;

  @override
  String toString() => message;
}

class RecipeValidator {
  RecipeValidator._(this._schema);

  factory RecipeValidator.fromSchemaString(String schemaSource) =>
      RecipeValidator._(
        JsonSchema.create(
          schemaSource,
          schemaVersion: SchemaVersion.draft2020_12,
        ),
      );

  final JsonSchema _schema;

  RecipeDocument validateSource(String source) {
    final dynamic decoded;
    try {
      // Accept only a whole document or an unambiguous outer JSON fence.
      // Explanations, nested fences and guessed/repaired JSON are rejected.
      final trimmed = source.trim();
      final fence = RegExp(r'^```json\s*\r?\n([\s\S]*?)\r?\n```$')
          .firstMatch(trimmed);
      decoded = jsonDecode(fence?.group(1) ?? trimmed);
    } on FormatException {
      throw const RecipeImportException(
        RecipeImportErrorCode.malformedJson,
        'レシピファイルを読み取れませんでした。正しい形式で書き出し直してください。',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const RecipeImportException(
        RecipeImportErrorCode.invalidRoot,
        'レシピの先頭構造が正しくありません。',
      );
    }
    return validateDocument(decoded);
  }

  RecipeDocument validateDocument(Map<String, dynamic> document) {
    final schemaVersion = document['schema_version'];
    if (schemaVersion is String &&
        schemaVersion != supportedRecipeSchemaVersion) {
      final legacy = schemaVersion == '1.0.0';
      throw RecipeImportException(
        RecipeImportErrorCode.unsupportedSchemaVersion,
        legacy
            ? '旧形式のレシピです。対応する新しい指示文でレシピを作り直してください。'
            : 'このレシピの形式（$schemaVersion）には対応していません。',
      );
    }
    final type = document['type'];
    if (type is String && type != 'recipe') {
      throw const RecipeImportException(
        RecipeImportErrorCode.unexpectedDocumentType,
        '選択したファイルはレシピではありません。',
      );
    }
    final result = _schema.validate(document);
    if (!result.isValid) {
      throw RecipeImportException(
        RecipeImportErrorCode.schemaViolation,
        '必須情報の不足または形式の誤りがあるため、取り込めませんでした。',
        details: result.errors
            .take(3)
            .map((error) => error.toString())
            .toList(growable: false),
      );
    }

    final recipe = document['recipe'] as Map<String, dynamic>;
    final ingredients = recipe['ingredients'] as List<dynamic>;
    final amounts = recipe['amounts'] as List<dynamic>;
    final utensils = recipe['utensils'] as List<dynamic>;
    final preparation = recipe['preparation'] as List<dynamic>;
    final stages = recipe['stages'] as List<dynamic>;
    final steps = <dynamic>[
      for (final stage in stages) ...(stage as Map)['steps'] as List,
    ];
    final problems = <String>[];
    bool uniqueIds(List<dynamic> items) =>
        items.map((item) => (item as Map)['id']).toSet().length == items.length;
    if (!uniqueIds(ingredients) ||
        !uniqueIds(amounts) ||
        !uniqueIds(utensils) ||
        !uniqueIds(preparation) ||
        !uniqueIds(stages) ||
        !uniqueIds(steps)) {
      problems.add('材料・分量・器具・事前準備・工程のIDは重複できません。');
    }
    final parentRevision = recipe['parent_revision'] as int?;
    if (parentRevision != null &&
        parentRevision >= (recipe['revision'] as int)) {
      problems.add('parent_revisionは現在のrevisionより小さくしてください。');
    }
    final servings = recipe['servings'] as int;
    final adjustment = recipe['serving_adjustment'] as Map<String, dynamic>;
    final minServings = adjustment['min_servings'] as int;
    final maxServings = adjustment['max_servings'] as int;
    if (minServings > servings || servings > maxServings) {
      problems.add('基準人数は対応人数の範囲内にしてください。');
    }

    final ingredientIds = ingredients
        .map((item) => (item as Map)['id'])
        .toSet();
    final amountIds = amounts.map((item) => (item as Map)['id']).toSet();
    final utensilIds = utensils.map((item) => (item as Map)['id']).toSet();
    final amountsByIngredient = <Object?, List<Map<dynamic, dynamic>>>{};
    for (final rawAmount in amounts) {
      final amount = rawAmount as Map<dynamic, dynamic>;
      final ingredientId = amount['ingredient_id'];
      if (!ingredientIds.contains(ingredientId)) {
        problems.add('分量 ${amount['id']} の材料参照が見つかりません。');
      }
      amountsByIngredient.putIfAbsent(ingredientId, () => []).add(amount);
    }
    for (final ingredientId in ingredientIds) {
      final entries = amountsByIngredient[ingredientId] ?? const [];
      if (entries.isEmpty) {
        problems.add('材料 $ingredientId に分量がありません。');
        continue;
      }
      final units = entries
          .map((item) => item['quantity'] as Map)
          .where((quantity) => quantity['kind'] == 'measured')
          .map((quantity) => quantity['unit'])
          .toSet();
      if (units.length > 1) {
        problems.add('材料 $ingredientId の計測単位が一致しません。');
      }
    }

    final referencedAmounts = <Object?>{};
    void validateOwner(Map<dynamic, dynamic> owner, String label) {
      final localIds = (owner['amount_ids'] as List<dynamic>).toSet();
      referencedAmounts.addAll(localIds);
      for (final id in localIds) {
        if (!amountIds.contains(id)) problems.add('$labelの分量参照 $id が見つかりません。');
      }
    }

    for (final rawPrep in preparation) {
      final prep = rawPrep as Map<dynamic, dynamic>;
      validateOwner(prep, '事前準備 ${prep['id']}');
      _validateText(
        prep['text'] as List<dynamic>,
        amountIds,
        problems,
        label: '事前準備 ${prep['id']}',
        localAmountIds: (prep['amount_ids'] as List<dynamic>).toSet(),
      );
    }
    for (final rawStep in steps) {
      final step = rawStep as Map<dynamic, dynamic>;
      validateOwner(step, '工程 ${step['id']}');
      final localIds = (step['amount_ids'] as List<dynamic>).toSet();
      for (final field in ['instruction', 'heat', 'done_when']) {
        final value = step[field];
        if (value is List) {
          _validateText(
            value,
            amountIds,
            problems,
            label: '工程 ${step['id']} の$field',
            localAmountIds: localIds,
          );
        }
      }
      for (final task in step['parallel_tasks'] as List<dynamic>) {
        _validateText(
          task as List<dynamic>,
          amountIds,
          problems,
          label: '工程 ${step['id']} のparallel_tasks',
          localAmountIds: localIds,
        );
      }
      final preview = step['next_preview'];
      if (preview is List) {
        _validateText(
          preview,
          amountIds,
          problems,
          label: '工程 ${step['id']} のnext_preview',
        );
      }
      for (final id in step['utensil_ids'] as List<dynamic>) {
        if (!utensilIds.contains(id)) {
          problems.add('工程 ${step['id']} の器具参照 $id が見つかりません。');
        }
      }
    }
    for (final id in amountIds.difference(referencedAmounts)) {
      problems.add('分量 $id は事前準備または工程から参照してください。');
    }
    for (final text in recipe['overview'] as List<dynamic>) {
      _validateText(text as List<dynamic>, amountIds, problems, label: '全体工程');
    }
    for (final ingredient in ingredients.cast<Map<dynamic, dynamic>>()) {
      final note = ingredient['note'];
      if (note is List) {
        _validateText(
          note,
          amountIds,
          problems,
          label: '材料 ${ingredient['id']} のnote',
        );
      }
    }
    for (final amount in amounts.cast<Map<dynamic, dynamic>>()) {
      final note = amount['note'];
      if (note is List) {
        _validateText(
          note,
          amountIds,
          problems,
          label: '分量 ${amount['id']} のnote',
        );
      }
    }
    for (final utensil in utensils.cast<Map<dynamic, dynamic>>()) {
      final note = utensil['reuse_note'];
      if (note is List) {
        _validateText(
          note,
          amountIds,
          problems,
          label: '器具 ${utensil['id']} のreuse_note',
        );
      }
    }
    for (final adjustment
        in (recipe['adjustments'] as List).cast<Map<dynamic, dynamic>>()) {
      _validateText(
        adjustment['condition'] as List<dynamic>,
        amountIds,
        problems,
        label: '調整条件',
      );
      _validateText(
        adjustment['action'] as List<dynamic>,
        amountIds,
        problems,
        label: '調整方法',
      );
    }
    for (final field in ['storage_note', 'lunchbox_note']) {
      final value = recipe[field];
      if (value is List) {
        _validateText(value, amountIds, problems, label: field);
      }
    }
    if (problems.isNotEmpty) {
      throw RecipeImportException(
        RecipeImportErrorCode.schemaViolation,
        problems.first,
        details: problems.take(3).toList(growable: false),
      );
    }
    final parsed = RecipeDocument.fromValidatedJson(document);
    try {
      for (var target = minServings; target <= maxServings; target++) {
        parsed.contextFor(target);
      }
    } catch (_) {
      throw const RecipeImportException(
        RecipeImportErrorCode.schemaViolation,
        '対応人数の分量を安全に計算できません。',
      );
    }
    return parsed;
  }

  static void _validateText(
    List<dynamic> text,
    Set<Object?> amountIds,
    List<String> problems, {
    required String label,
    Set<Object?>? localAmountIds,
  }) {
    for (final rawSegment in text) {
      final segment = rawSegment as Map;
      if (segment['type'] != 'amount_ref') continue;
      final id = segment['amount_id'];
      if (!amountIds.contains(id)) {
        problems.add('$labelの文章内分量参照 $id が見つかりません。');
      } else if (localAmountIds != null && !localAmountIds.contains(id)) {
        problems.add('$labelの文章内分量参照 $id をamount_idsにも含めてください。');
      }
    }
  }
}
