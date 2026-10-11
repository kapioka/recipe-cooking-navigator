import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_cooking_navigator/domain/recipe_validator.dart';

void main() {
  late RecipeValidator validator;
  late String validRecipeSource;

  setUpAll(() async {
    final schema = await File('schemas/recipe-v2.schema.json').readAsString();
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
    document['schema_version'] = '9.0.0';

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

  test('rejects v1 with a dedicated recreation message', () {
    final document = jsonDecode(validRecipeSource) as Map<String, dynamic>;
    document['schema_version'] = '1.0.0';

    expect(
      () => validator.validateDocument(document),
      throwsA(
        isA<RecipeImportException>()
            .having(
              (error) => error.code,
              'code',
              RecipeImportErrorCode.unsupportedSchemaVersion,
            )
            .having((error) => error.message, 'message', contains('旧形式')),
      ),
    );
  });

  test(
    'rejects unknown units, unused amounts, and fixed amounts without reasons',
    () {
      final unknownUnit = jsonDecode(validRecipeSource) as Map<String, dynamic>;
      final unknownRecipe = unknownUnit['recipe'] as Map<String, dynamic>;
      final firstAmount = (unknownRecipe['amounts'] as List).first as Map;
      firstAmount['quantity']['unit'] = 'cup';
      expect(
        () => validator.validateDocument(unknownUnit),
        throwsA(isA<RecipeImportException>()),
      );

      final unused = jsonDecode(validRecipeSource) as Map<String, dynamic>;
      final unusedRecipe = unused['recipe'] as Map<String, dynamic>;
      (unusedRecipe['ingredients'] as List).add({
        'id': 'unused',
        'name': '未使用材料',
      });
      (unusedRecipe['amounts'] as List).add({
        'id': 'unused-amount',
        'ingredient_id': 'unused',
        'label': '全量',
        'quantity': {
          'kind': 'measured',
          'value': {'numerator': 1, 'denominator': 1},
          'unit': 'g',
          'scaling': 'linear',
        },
      });
      expect(
        () => validator.validateDocument(unused),
        throwsA(isA<RecipeImportException>()),
      );

      final missingReason =
          jsonDecode(validRecipeSource) as Map<String, dynamic>;
      final missingRecipe = missingReason['recipe'] as Map<String, dynamic>;
      final oil = (missingRecipe['amounts'] as List)[2] as Map;
      (oil['quantity'] as Map).remove('adjustment_note');
      expect(
        () => validator.validateDocument(missingReason),
        throwsA(isA<RecipeImportException>()),
      );
    },
  );

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
