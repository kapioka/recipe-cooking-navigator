import 'dart:convert';

class RecipeDocument {
  RecipeDocument._({
    required this.raw,
    required this.id,
    required this.revision,
    required this.parentRevision,
    required this.title,
    required this.servings,
    required this.totalTimeMinutes,
    required this.estimatedDifficulty,
    required this.ingredients,
    required this.overview,
  });

  factory RecipeDocument.fromValidatedJson(Map<String, dynamic> document) {
    final recipe = document['recipe'] as Map<String, dynamic>;
    final difficulty = recipe['estimated_difficulty'] as Map<String, dynamic>;

    return RecipeDocument._(
      raw: _copyJson(document),
      id: recipe['id'] as String,
      revision: recipe['revision'] as int,
      parentRevision: recipe['parent_revision'] as int?,
      title: recipe['title'] as String,
      servings: recipe['servings'] as int,
      totalTimeMinutes: recipe['total_time_minutes'] as int,
      estimatedDifficulty: difficulty['score'] as int,
      ingredients: (recipe['ingredients'] as List<dynamic>)
          .map((item) {
            final ingredient = item as Map<String, dynamic>;
            final quantity = ingredient['quantity'] as Map<String, dynamic>;
            return RecipeIngredient(
              name: ingredient['name'] as String,
              quantity: quantity['display'] as String,
              note: ingredient['note'] as String?,
            );
          })
          .toList(growable: false),
      overview: (recipe['overview'] as List<dynamic>).cast<String>(),
    );
  }

  final Map<String, dynamic> raw;
  final String id;
  final int revision;
  final int? parentRevision;
  final String title;
  final int servings;
  final int totalTimeMinutes;
  final int estimatedDifficulty;
  final List<RecipeIngredient> ingredients;
  final List<String> overview;

  static Map<String, dynamic> _copyJson(Map<String, dynamic> value) {
    return jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
  }
}

class RecipeIngredient {
  const RecipeIngredient({
    required this.name,
    required this.quantity,
    this.note,
  });

  final String name;
  final String quantity;
  final String? note;
}
