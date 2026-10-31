import '../domain/ai_recipe_request.dart';
import 'recipe_library_controller.dart';

Future<RecipeImportPreparation> prepareAiRecipe(
  RecipeLibraryController library,
  AiRecipeRequest request,
  String source, {
  RecipeImportPreview? replacing,
}) => library.prepareImportSource(
  source,
  replacing: replacing,
  accepts: (preview) {
    final recreation = request.recreation;
    if (recreation != null) {
      final base = (recreation['recipe_snapshot'] as Map)['recipe'] as Map;
      return preview.recipeId == base['id'] &&
          preview.parentRevision == base['revision'] &&
          preview.revision == recreation['next_revision'] &&
          library.revisionFor(preview.recipeId, preview.parentRevision!) !=
              null &&
          (library.revisionFor(preview.recipeId, preview.revision) == null ||
              library.isStoredPreview(preview));
    }
    final feedback = request.feedback;
    if (feedback == null) {
      return (request.conditions == null ||
              preview.servings == request.conditions!['servings']) &&
          preview.revision == 1 &&
          preview.parentRevision == null &&
          (library.revisionsFor(preview.recipeId).isEmpty ||
              library.isStoredPreview(preview));
    }
    final base = (feedback['recipe_snapshot'] as Map)['recipe'] as Map;
    final revisionRequest = feedback['revision_request'] as Map;
    return preview.recipeId == base['id'] &&
        preview.parentRevision == base['revision'] &&
        preview.revision == revisionRequest['next_revision'] &&
        library.revisionFor(preview.recipeId, preview.parentRevision!) !=
            null &&
        (library.revisionFor(preview.recipeId, preview.revision) == null ||
            library.isStoredPreview(preview));
  },
);
