import 'dart:convert';

import 'package:json_schema/json_schema.dart';

import 'recipe_document.dart';

const supportedRecipeSchemaVersion = '1.0.0';

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

  factory RecipeValidator.fromSchemaString(String schemaSource) {
    return RecipeValidator._(
      JsonSchema.create(
        schemaSource,
        schemaVersion: SchemaVersion.draft2020_12,
      ),
    );
  }

  final JsonSchema _schema;

  RecipeDocument validateSource(String source) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(source);
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
      throw RecipeImportException(
        RecipeImportErrorCode.unsupportedSchemaVersion,
        'このレシピの形式（$schemaVersion）にはまだ対応していません。',
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
    final ingredients = recipe['ingredients'] as List;
    final utensils = recipe['utensils'] as List;
    final preparation = recipe['preparation'] as List;
    final stages = recipe['stages'] as List;
    final steps = [for (final stage in stages) ...stage['steps'] as List];
    bool uniqueIds(List items) =>
        items.map((e) => e['id']).toSet().length == items.length;
    final ingredientIds = ingredients.map((e) => e['id']).toSet();
    final utensilIds = utensils.map((e) => e['id']).toSet();
    final uses = [
      for (final step in steps) ...step['ingredient_uses'] as List,
      for (final prep in preparation) ...?prep['ingredient_uses'] as List?,
    ];
    final parentRevision = recipe['parent_revision'] as int?;
    if (parentRevision != null &&
            parentRevision >= (recipe['revision'] as int) ||
        !uniqueIds(ingredients) ||
        !uniqueIds(utensils) ||
        !uniqueIds(preparation) ||
        !uniqueIds(stages) ||
        !uniqueIds(steps) ||
        uses.any((use) => !ingredientIds.contains(use['ingredient_id'])) ||
        steps.any(
          (step) => (step['utensil_ids'] as List).any(
            (id) => !utensilIds.contains(id),
          ),
        )) {
      throw const RecipeImportException(
        RecipeImportErrorCode.schemaViolation,
        '履歴または材料・器具・事前準備・工程のIDか参照が正しくありません。',
      );
    }
    return RecipeDocument.fromValidatedJson(document);
  }
}
