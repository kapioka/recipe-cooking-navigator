import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_cooking_navigator/domain/recipe_validator.dart';

void main() {
  late RecipeValidator validator;
  late String validRecipeSource;

  setUpAll(() async {
    final schema = await File('schemas/recipe-v1.schema.json').readAsString();
    validRecipeSource = await File('examples/recipe-example.json')
        .readAsString();
    validator = RecipeValidator.fromSchemaString(schema);
  });

  test('accepts the checked-in recipe example', () {
    final recipe = validator.validateSource(validRecipeSource);

    expect(recipe.id, 'ginger-pork-001');
    expect(recipe.revision, 1);
    expect(recipe.title, '豚の生姜焼き');
  });

  test('rejects malformed JSON', () {
    expect(
      () => validator.validateSource('{not valid'),
      throwsA(
        isA<RecipeImportException>().having(
          (error) => error.code,
          'code',
          RecipeImportErrorCode.malformedJson,
        ),
      ),
    );
  });

  test('rejects a recipe with missing required fields', () {
    final document = jsonDecode(validRecipeSource) as Map<String, dynamic>;
    final recipe = document['recipe'] as Map<String, dynamic>;
    recipe.remove('title');

    expect(
      () => validator.validateDocument(document),
      throwsA(
        isA<RecipeImportException>().having(
          (error) => error.code,
          'code',
          RecipeImportErrorCode.schemaViolation,
        ),
      ),
    );
  });

  test('rejects an unsupported schema version before saving', () {
    final document = jsonDecode(validRecipeSource) as Map<String, dynamic>;
    document['schema_version'] = '2.0.0';

    expect(
      () => validator.validateDocument(document),
      throwsA(
        isA<RecipeImportException>().having(
          (error) => error.code,
          'code',
          RecipeImportErrorCode.unsupportedSchemaVersion,
        ),
      ),
    );
  });

  test('rejects fields not defined by the schema', () {
    final document = jsonDecode(validRecipeSource) as Map<String, dynamic>;
    document['unexpected'] = true;

    expect(
      () => validator.validateDocument(document),
      throwsA(
        isA<RecipeImportException>().having(
          (error) => error.code,
          'code',
          RecipeImportErrorCode.schemaViolation,
        ),
      ),
    );
  });

  test('rejects duplicate IDs and dangling references', () {
    final duplicateStage =
        jsonDecode(validRecipeSource) as Map<String, dynamic>;
    final recipe = duplicateStage['recipe'] as Map<String, dynamic>;
    final stages = recipe['stages'] as List;
    stages.add(jsonDecode(jsonEncode(stages.first)));

    expect(
      () => validator.validateDocument(duplicateStage),
      throwsA(isA<RecipeImportException>()),
    );

    final danglingUtensil =
        jsonDecode(validRecipeSource) as Map<String, dynamic>;
    final danglingRecipe = danglingUtensil['recipe'] as Map<String, dynamic>;
    final firstStage = (danglingRecipe['stages'] as List).first as Map;
    final firstStep = (firstStage['steps'] as List).first as Map;
    (firstStep['utensil_ids'] as List).add('missing-utensil');

    expect(
      () => validator.validateDocument(danglingUtensil),
      throwsA(isA<RecipeImportException>()),
    );
  });

  test('rejects a parent revision that is not older', () {
    final document = jsonDecode(validRecipeSource) as Map<String, dynamic>;
    final recipe = document['recipe'] as Map<String, dynamic>;
    recipe['revision'] = 2;
    recipe['parent_revision'] = 2;

    expect(
      () => validator.validateDocument(document),
      throwsA(isA<RecipeImportException>()),
    );
  });
}
