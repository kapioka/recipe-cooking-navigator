import 'dart:convert';

import 'cooking_context.dart';
import 'recipe_amount.dart';
import 'recipe_text.dart';

class RecipeDocument {
  RecipeDocument._({
    required this.raw,
    required this.id,
    required this.revision,
    required this.parentRevision,
    required this.title,
    required this.servings,
    required this.minServings,
    required this.maxServings,
    required this.servingAdjustmentNote,
    required this.totalTimeMinutes,
    required this.estimatedDifficulty,
    required this.ingredients,
    required this.amounts,
    required this.overview,
  }) : _ingredientsById = {for (final item in ingredients) item.id: item},
       _amountsById = {for (final item in amounts) item.id: item};

  factory RecipeDocument.fromValidatedJson(Map<String, dynamic> document) {
    final recipe = document['recipe'] as Map<String, dynamic>;
    final difficulty = recipe['estimated_difficulty'] as Map<String, dynamic>;
    final adjustment = recipe['serving_adjustment'] as Map<String, dynamic>;
    return RecipeDocument._(
      raw: copyJson(document),
      id: recipe['id'] as String,
      revision: recipe['revision'] as int,
      parentRevision: recipe['parent_revision'] as int?,
      title: recipe['title'] as String,
      servings: recipe['servings'] as int,
      minServings: adjustment['min_servings'] as int,
      maxServings: adjustment['max_servings'] as int,
      servingAdjustmentNote: adjustment['note'] as String,
      totalTimeMinutes: recipe['total_time_minutes'] as int,
      estimatedDifficulty: difficulty['score'] as int,
      ingredients: (recipe['ingredients'] as List<dynamic>)
          .map((item) {
            final ingredient = item as Map<String, dynamic>;
            return RecipeIngredient(
              id: ingredient['id'] as String,
              name: ingredient['name'] as String,
              note: ingredient['note'] as List<dynamic>?,
            );
          })
          .toList(growable: false),
      amounts: (recipe['amounts'] as List<dynamic>)
          .map((item) {
            final amount = item as Map<String, dynamic>;
            return RecipeAmount(
              id: amount['id'] as String,
              ingredientId: amount['ingredient_id'] as String,
              label: amount['label'] as String,
              quantity: Map<String, dynamic>.from(amount['quantity'] as Map),
              note: amount['note'] as List<dynamic>?,
            );
          })
          .toList(growable: false),
      overview: (recipe['overview'] as List<dynamic>)
          .map((item) => List<dynamic>.from(item as List))
          .toList(growable: false),
    );
  }

  final Map<String, dynamic> raw;
  final String id;
  final int revision;
  final int? parentRevision;
  final String title;
  final int servings;
  final int minServings;
  final int maxServings;
  final String servingAdjustmentNote;
  final int totalTimeMinutes;
  final int estimatedDifficulty;
  final List<RecipeIngredient> ingredients;
  final List<RecipeAmount> amounts;
  final List<List<dynamic>> overview;
  final Map<String, RecipeIngredient> _ingredientsById;
  final Map<String, RecipeAmount> _amountsById;

  Map<String, dynamic> get recipeData => raw['recipe'] as Map<String, dynamic>;

  List<Map<String, dynamic>> get steps => [
    for (final stage in recipeData['stages'] as List)
      for (final step in stage['steps'] as List)
        Map<String, dynamic>.from(step as Map),
  ];

  CookingContext contextFor(int targetServings) {
    if (targetServings < minServings || targetServings > maxServings) {
      throw RangeError.range(
        targetServings,
        minServings,
        maxServings,
        'targetServings',
      );
    }
    return CookingContext(
      targetServings: targetServings,
      resolvedAmounts: amounts
          .map((amount) {
            final quantity = amount.quantity;
            if (quantity['kind'] == 'qualitative') {
              return ResolvedAmount(
                amountId: amount.id,
                quantity: ResolvedQuantity.qualitative(
                  quantity['text'] as String,
                  quantity['adjustment_note'] as String,
                ),
              );
            }
            final rawValue = quantity['value'] as Map<String, dynamic>;
            var value = Rational.fromNumbers(
              rawValue['numerator'] as int,
              rawValue['denominator'] as int,
            );
            if (quantity['scaling'] == 'linear') {
              value = value.scale(targetServings, servings);
            }
            return ResolvedAmount(
              amountId: amount.id,
              quantity: ResolvedQuantity.measured(
                value,
                quantity['unit'] as String,
              ),
            );
          })
          .toList(growable: false),
    );
  }

  void validateContext(CookingContext context) {
    if (context.scalingAlgorithm != servingsScalingAlgorithm ||
        !contextFor(context.targetServings).jsonEquals(context)) {
      throw const FormatException('保存した人数または分量がRecipe原本と一致しません。');
    }
  }

  RenderedRecipeText renderText(List<dynamic> text, CookingContext context) {
    final display = StringBuffer();
    final speech = StringBuffer();
    for (final rawSegment in text) {
      final segment = rawSegment as Map<String, dynamic>;
      if (segment['type'] == 'text') {
        display.write(segment['text'] as String);
        speech.write(segment['text'] as String);
      } else {
        final amountId = segment['amount_id'] as String;
        final amount = _amountsById[amountId]!;
        final ingredient = _ingredientsById[amount.ingredientId]!;
        final quantity = context.byId[amountId]!.quantity;
        final rendered = _renderQuantity(quantity);
        display.write('${ingredient.name} ${rendered.display}');
        speech.write('${ingredient.name} ${rendered.speech}');
      }
    }
    return RenderedRecipeText(
      displayText: display.toString(),
      speechText: speech.toString(),
    );
  }

  List<String> ingredientsFor(
    Map<String, dynamic> owner,
    CookingContext context,
  ) => [
    for (final amountId in owner['amount_ids'] as List<dynamic>)
      amountLine(amountId as String, context),
  ];

  String amountLine(String amountId, CookingContext context) {
    final amount = _amountsById[amountId]!;
    final ingredient = _ingredientsById[amount.ingredientId]!;
    final quantity = context.byId[amountId]!.quantity;
    final rendered = _renderQuantity(quantity).display;
    final notes = <String>[
      if (amount.isFixed && context.targetServings != servings)
        '人数によらず同量${amount.adjustmentNote == null ? '' : '：${amount.adjustmentNote}'}',
      if (quantity.kind == 'qualitative') quantity.adjustmentNote!,
      if (amount.note != null) renderText(amount.note!, context).displayText,
    ];
    return '${ingredient.name} $rendered${notes.isEmpty ? '' : '（${notes.join('／')}）'}';
  }

  String amountSpeech(String amountId, CookingContext context) {
    final amount = _amountsById[amountId]!;
    final ingredient = _ingredientsById[amount.ingredientId]!;
    final quantity = context.byId[amountId]!.quantity;
    final rendered = _renderQuantity(quantity).speech;
    final notes = <String>[
      if (amount.isFixed && context.targetServings != servings)
        '人数によらず同量です。${amount.adjustmentNote ?? ''}',
      if (quantity.kind == 'qualitative') quantity.adjustmentNote!,
    ];
    return '${ingredient.name} $rendered${notes.isEmpty ? '' : '。${notes.join('。')}'}';
  }

  List<RecipeIngredientSummary> ingredientSummaries(CookingContext context) {
    return ingredients
        .map((ingredient) {
          final ingredientAmounts = amounts
              .where((amount) => amount.ingredientId == ingredient.id)
              .toList(growable: false);
          final measured = ingredientAmounts
              .map((amount) => context.byId[amount.id]!.quantity)
              .where((quantity) => quantity.kind == 'measured')
              .toList(growable: false);
          final qualitative = ingredientAmounts
              .where(
                (amount) =>
                    context.byId[amount.id]!.quantity.kind == 'qualitative',
              )
              .toList(growable: false);
          final parts = <String>[];
          if (measured.isNotEmpty) {
            var total = measured.first.value!;
            for (final quantity in measured.skip(1)) {
              total += quantity.value!;
            }
            final totalText = formatMeasuredAmount(
              total,
              measured.first.unit!,
            ).display;
            parts.add(measured.length > 1 ? '合計 $totalText' : totalText);
          }
          parts.addAll(
            qualitative.map((amount) {
              final quantity = context.byId[amount.id]!.quantity;
              return '${amount.label}：${quantity.text}';
            }),
          );
          final details = ingredientAmounts.length > 1
              ? ingredientAmounts
                    .map(
                      (amount) =>
                          '${amount.label}：${_renderQuantity(context.byId[amount.id]!.quantity).display}',
                    )
                    .join('／')
              : null;
          return RecipeIngredientSummary(
            id: ingredient.id,
            name: ingredient.name,
            quantity: parts.join(' ＋ '),
            details: details,
            note: ingredient.note == null
                ? null
                : renderText(ingredient.note!, context).displayText,
          );
        })
        .toList(growable: false);
  }

  FormattedAmount _renderQuantity(ResolvedQuantity quantity) {
    if (quantity.kind == 'measured') {
      return formatMeasuredAmount(quantity.value!, quantity.unit!);
    }
    return FormattedAmount(display: quantity.text!, speech: quantity.text!);
  }

  static Map<String, dynamic> copyJson(Map<String, dynamic> value) =>
      jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
}

class RecipeIngredient {
  const RecipeIngredient({required this.id, required this.name, this.note});
  final String id;
  final String name;
  final List<dynamic>? note;
}

class RecipeIngredientSummary {
  const RecipeIngredientSummary({
    required this.id,
    required this.name,
    required this.quantity,
    this.details,
    this.note,
  });
  final String id;
  final String name;
  final String quantity;
  final String? details;
  final String? note;
}
