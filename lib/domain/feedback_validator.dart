import 'dart:convert';

import 'package:json_schema/json_schema.dart';

import 'cooking_context.dart';
import 'recipe_document.dart';
import 'recipe_validator.dart';

class FeedbackValidationException implements Exception {
  const FeedbackValidationException(this.message, {this.details = const []});
  final String message;
  final List<String> details;
  @override
  String toString() => message;
}

class FeedbackValidator {
  FeedbackValidator._(this._schema, this._recipeValidator);

  factory FeedbackValidator.fromSchemaStrings({
    required String feedbackSchemaSource,
    required String recipeSchemaSource,
  }) {
    final recipeSchemaJson = jsonDecode(recipeSchemaSource);
    final provider = RefProvider.sync((String ref) {
      if (ref.endsWith('/recipe-v2.schema.json') ||
          ref.endsWith('/recipe-v2.schema.json#') ||
          ref == 'recipe-v2.schema.json') {
        return recipeSchemaJson;
      }
      return null;
    });
    return FeedbackValidator._(
      JsonSchema.create(
        feedbackSchemaSource,
        schemaVersion: SchemaVersion.draft2020_12,
        refProvider: provider,
      ),
      RecipeValidator.fromSchemaString(recipeSchemaSource),
    );
  }

  final JsonSchema _schema;
  final RecipeValidator _recipeValidator;

  Map<String, dynamic> validateSource(String source) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const FeedbackValidationException('Feedback JSONを読み取れません。');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FeedbackValidationException('Feedbackの先頭構造が正しくありません。');
    }
    return validateDocument(decoded);
  }

  Map<String, dynamic> validateDocument(Map<String, dynamic> document) {
    final result = _schema.validate(document);
    if (!result.isValid) {
      throw FeedbackValidationException(
        'Feedbackの必須情報または形式が正しくありません。',
        details: result.errors
            .take(3)
            .map((error) => error.toString())
            .toList(growable: false),
      );
    }
    final improvement = _recipeValidator.validateDocument(
      Map<String, dynamic>.from(document['recipe_snapshot'] as Map),
    );
    final session = document['cook_session'] as Map<String, dynamic>;
    final cooked = _recipeValidator.validateDocument(
      Map<String, dynamic>.from(session['recipe_snapshot'] as Map),
    );
    if (improvement.id != cooked.id ||
        session['recipe_id'] != cooked.id ||
        session['recipe_revision'] != cooked.revision) {
      throw const FeedbackValidationException('改善元と実際に調理したRecipeの識別情報が一致しません。');
    }
    final context = CookingContext.fromJson(
      Map<String, dynamic>.from(session['cooking_context'] as Map),
    );
    try {
      cooked.validateContext(context);
    } on FormatException catch (error) {
      throw FeedbackValidationException(error.message);
    }
    final nextRevision =
        (document['revision_request'] as Map<String, dynamic>)['next_revision']
            as int;
    if (nextRevision <= improvement.revision ||
        nextRevision <= cooked.revision) {
      throw const FeedbackValidationException(
        'next_revisionは改善元と実調理Recipeのrevisionより大きくしてください。',
      );
    }
    return RecipeDocument.copyJson(document);
  }
}

class FeedbackCookingSource {
  const FeedbackCookingSource({
    required this.recipeId,
    required this.recipeRevision,
    required this.recipeSnapshot,
    required this.cookingContext,
  });

  factory FeedbackCookingSource.fromStoredSession(
    Map<String, dynamic> session,
  ) {
    return FeedbackCookingSource(
      recipeId: session['recipe_id'] as String,
      recipeRevision: session['revision'] as int,
      recipeSnapshot: RecipeDocument.copyJson(
        Map<String, dynamic>.from(session['recipe_snapshot'] as Map),
      ),
      cookingContext: CookingContext.fromJson(
        Map<String, dynamic>.from(session['cooking_context'] as Map),
      ),
    );
  }

  final String recipeId;
  final int recipeRevision;
  final Map<String, dynamic> recipeSnapshot;
  final CookingContext cookingContext;
}
