import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_cooking_navigator/domain/recipe_amount.dart';
import 'package:recipe_cooking_navigator/domain/recipe_validator.dart';

void main() {
  late RecipeValidator validator;
  late Map<String, dynamic> source;

  setUpAll(() async {
    validator = RecipeValidator.fromSchemaString(
      await File('schemas/recipe-v2.schema.json').readAsString(),
    );
    source = jsonDecode(
      await File('examples/recipe-example.json').readAsString(),
    ) as Map<String, dynamic>;
  });

  Map<String, dynamic> copySource() =>
      jsonDecode(jsonEncode(source)) as Map<String, dynamic>;

  test('Q01-Q05 resolves from the base rational without cumulative error', () {
    final raw = copySource();
    final recipe = raw['recipe'] as Map<String, dynamic>;
    recipe['servings'] = 3;
    (recipe['serving_adjustment'] as Map)['min_servings'] = 2;
    (recipe['serving_adjustment'] as Map)['max_servings'] = 4;
    final pork = (recipe['amounts'] as List).first as Map;
    pork['quantity']['value']['numerator'] = 300;
    final document = validator.validateDocument(raw);

    expect(
      document.amountLine('pork-all', document.contextFor(2)),
      contains('200g'),
    );
    expect(
      document.amountLine('pork-all', document.contextFor(4)),
      contains('400g'),
    );

    pork['quantity']['value']['numerator'] = 200;
    final thirds = validator.validateDocument(raw);
    expect(
      thirds.amountLine('pork-all', thirds.contextFor(4)),
      contains('約266.67g'),
    );
    expect(
      thirds.contextFor(3).byId['pork-all']!.quantity.value,
      Rational.fromNumbers(200, 1),
    );

    final onion = thirds.contextFor(4).byId['onion-all']!.quantity.value!;
    expect(onion, Rational.fromNumbers(2, 3));
    expect(formatMeasuredAmount(onion, 'piece').display, '2/3個');
    expect(formatMeasuredAmount(onion, 'piece').speech, '3分の2個');
  });

  test('Q06 fixed amount stays unchanged and explains why', () {
    final document = validator.validateDocument(copySource());
    final line = document.amountLine('oil-frying', document.contextFor(4));
    expect(line, contains('小さじ1'));
    expect(line, contains('人数によらず同量'));
  });

  test('Q07 and Q10 keep qualitative values non-numeric', () async {
    final document = validator.validateSource(
      await File('examples/recipe-v2-split-example.json').readAsString(),
    );
    final summary = document
        .ingredientSummaries(document.contextFor(3))
        .singleWhere((item) => item.name == '塩');
    expect(summary.quantity, '仕上げ用：少々');
    expect(
      document.amountLine('salt-finish', document.contextFor(3)),
      contains('味見'),
    );
  });

  test('Q08-Q09 totals each amount once even when references repeat', () async {
    final document = validator.validateSource(
      await File('examples/recipe-v2-split-example.json').readAsString(),
    );
    final summary = document
        .ingredientSummaries(document.contextFor(3))
        .singleWhere((item) => item.name == 'たれ');
    expect(summary.quantity, contains('合計 150g'));
    expect(summary.quantity, contains('仕上げ調整：適量'));
    expect(summary.details, contains('加熱用：45g'));
    expect(summary.details, contains('仕上げ用：105g'));
  });

  test('Q11 RecipeText changes amount refs but not ordinary numbers', () {
    final document = validator.validateDocument(copySource());
    final text = <dynamic>[
      {'type': 'text', 'text': '厚さ1cmにして'},
      {'type': 'amount_ref', 'amount_id': 'pork-all'},
      {'type': 'text', 'text': 'を使う。'},
    ];
    expect(
      document.renderText(text, document.contextFor(4)).displayText,
      contains('厚さ1cm'),
    );
    expect(
      document.renderText(text, document.contextFor(4)).displayText,
      contains('400g'),
    );
  });

  test('Q13 tiny positive values never display as zero', () {
    expect(
      formatMeasuredAmount(Rational.fromNumbers(1, 1000), 'g').display,
      '1/1000g',
    );
  });

  test('Q14 fixed serving range resolves only its base serving', () {
    final raw = copySource();
    final recipe = raw['recipe'] as Map<String, dynamic>;
    final adjustment = recipe['serving_adjustment'] as Map<String, dynamic>;
    adjustment['min_servings'] = 2;
    adjustment['max_servings'] = 2;
    final document = validator.validateDocument(raw);
    expect(document.contextFor(2).targetServings, 2);
    expect(() => document.contextFor(3), throwsRangeError);
  });

  test('Q15 exact rational totals remain exact', () {
    final third = Rational.fromNumbers(1, 3);
    expect(third + third + third, Rational.fromNumbers(1, 1));
    expect(formatMeasuredAmount(third, 'g').display, '約0.33g');
  });
}
