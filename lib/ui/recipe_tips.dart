import 'package:flutter/material.dart';

import '../domain/cooking_context.dart';
import '../domain/recipe_document.dart';

/// Optional recipe-wide advice, kept out of the working instructions and TTS.
class RecipeTips extends StatelessWidget {
  const RecipeTips({
    required this.recipe,
    required this.cookingContext,
    super.key,
  });

  final RecipeDocument recipe;
  final CookingContext cookingContext;

  @override
  Widget build(BuildContext context) {
    final tips = recipe.recipeData['adjustments'] as List;
    if (tips.isEmpty) return const SizedBox.shrink();
    String render(dynamic text) =>
        recipe.renderText(text as List, cookingContext).displayText;
    return ExpansionTile(
      title: const Text('コツ・失敗対策'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final tip in tips)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  render(tip['condition']),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(render(tip['action'])),
              ],
            ),
          ),
      ],
    );
  }
}
