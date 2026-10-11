import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_cooking_navigator/domain/ai_recipe_request.dart';
import 'package:recipe_cooking_navigator/domain/feedback_validator.dart';
import 'package:recipe_cooking_navigator/domain/recipe_validator.dart';

void main() {
  late RecipeValidator recipeValidator;
  late FeedbackValidator feedbackValidator;
  late String source;
  setUpAll(() async {
    final recipeSchema = await File('schemas/recipe-v2.schema.json')
        .readAsString();
    recipeValidator = RecipeValidator.fromSchemaString(recipeSchema);
    feedbackValidator = FeedbackValidator.fromSchemaStrings(
      recipeSchemaSource: recipeSchema,
      feedbackSchemaSource: await File('schemas/feedback-v2.schema.json')
          .readAsString(),
    );
    source = await File('examples/recipe-example.json').readAsString();
  });

  test('request contains only explicit conditions and public version/stop contract', () {
    final request = AiRecipeRequest.generate(
      ingredients: '鶏肉\n玉ねぎ',
      servings: 3,
      utensils: '鍋',
      taste: '薄味',
      timeMinutes: 25,
    );
    expect(request.text, contains(publicAiRouterUrl));
    expect(request.text, contains('2.0.0'));
    expect(request.text, contains('推測生成しない'));
    final data = jsonDecode(request.text.split('\n').last) as Map;
    expect(data['servings'], 3);
    expect(data['ingredients'], '鶏肉\n玉ねぎ');
    expect(data.keys, isNot(contains('profile')));
    expect(
      () => AiRecipeRequest.generate(
        ingredients: ' ',
        servings: 2,
        utensils: '',
        taste: '',
        timeMinutes: 30,
      ),
      throwsFormatException,
    );
    expect(
      () => AiRecipeRequest.generate(
        ingredients: '米',
        servings: 0,
        utensils: '',
        taste: '',
        timeMinutes: 30,
      ),
      throwsFormatException,
    );
  });

  test(
    'selected feedback is validated and carries the chosen revision',
    () async {
      final feedback = jsonDecode(
        await File('examples/feedback-example.json').readAsString(),
      ) as Map<String, dynamic>;
      final request = AiRecipeRequest.improve(
        feedback: feedback,
        validator: feedbackValidator,
      );
      final data = jsonDecode(request.text.split('\n').last) as Map;
      expect(data, feedback);
      expect(data['recipe_snapshot'], feedback['recipe_snapshot']);
      final invalid = Map<String, dynamic>.from(feedback)
        ..['schema_version'] = '9.0.0';
      expect(
        () => AiRecipeRequest.improve(
          feedback: invalid,
          validator: feedbackValidator,
        ),
        throwsA(isA<FeedbackValidationException>()),
      );
    },
  );

  test('only the whole JSON or one outer json fence is accepted', () {
    final recipe = recipeValidator.validateSource(source);
    expect(
      recipeValidator.validateSource(' \n```json\n$source\n``` \n').id,
      recipe.id,
    );
    expect(
      recipeValidator.validateSource('```json\r\n$source\r\n```').id,
      recipe.id,
    );
    for (final ambiguous in [
      '説明\n$source',
      '$source\n説明',
      '```\n$source\n```',
      '```json\n$source\n```\n```json\n$source\n```',
      '{broken',
    ]) {
      expect(
        () => recipeValidator.validateSource(ambiguous),
        throwsA(isA<RecipeImportException>()),
      );
    }
    final unsupported = jsonDecode(source) as Map<String, dynamic>;
    unsupported['schema_version'] = '99.0.0';
    expect(
      () => recipeValidator.validateSource(
        '```json\n${jsonEncode(unsupported)}\n```',
      ),
      throwsA(isA<RecipeImportException>()),
    );
  });
}
