import 'package:flutter/material.dart';

import '../application/recipe_library_controller.dart';
import '../domain/recipe_document.dart';
import 'recipe_photo_avatar.dart';
import 'recipe_theme.dart';

/// The same recipe identity in reading and reflection screens.
class RecipeHeading extends StatelessWidget {
  const RecipeHeading({
    required this.recipe,
    required this.controller,
    super.key,
  });
  final RecipeDocument recipe;
  final RecipeLibraryController controller;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final photo = RecipePhotoAvatar(
        library: controller,
        recipeId: recipe.id,
        recipeTitle: recipe.title,
      );
      final title = Semantics(
        header: true,
        child: Text(recipe.title, style: RecipeTheme.detailRecipeTitle),
      );
      if (bounds.maxWidth < 300 ||
          MediaQuery.textScalerOf(context).scale(24) > 32) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [photo, const SizedBox(height: 12), title],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          photo,
          const SizedBox(width: 16),
          Expanded(child: title),
        ],
      );
    },
  );
}
