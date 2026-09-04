import 'package:flutter/material.dart';

import '../domain/recipe_document.dart';

class RecipeDetailScreen extends StatelessWidget {
  const RecipeDetailScreen({required this.recipe, super.key});

  final RecipeDocument recipe;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('レシピ詳細')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(recipe.title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text('${recipe.servings}人分')),
              Chip(label: Text('${recipe.totalTimeMinutes}分')),
              Chip(label: Text('AI想定難易度 ${recipe.estimatedDifficulty}')),
              Chip(label: Text('Version ${recipe.revision}')),
            ],
          ),
          const SizedBox(height: 24),
          Text('材料', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ...recipe.ingredients.map(
            (ingredient) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(ingredient.name),
              trailing: Text(ingredient.quantity),
              subtitle: ingredient.note == null ? null : Text(ingredient.note!),
            ),
          ),
          const SizedBox(height: 20),
          Text('全体工程', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ...recipe.overview.indexed.map(
            (entry) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(radius: 13, child: Text('${entry.$1 + 1}')),
                  const SizedBox(width: 12),
                  Expanded(child: Text(entry.$2)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
