import '../domain/ai_recipe_request.dart';
import 'recipe_library_controller.dart';

Future<RecipeImportPreparation> prepareAiRecipe(
  RecipeLibraryController library,
  AiRecipeRequest request,
  String source,
) async {
  final preparation = await library.prepareImportSource(source);
  final preview = preparation.preview;
  if (preview == null) return preparation;
  final feedback = request.feedback;
  bool matches;
  if (feedback == null) {
    matches =
        preview.revision == 1 &&
        preview.parentRevision == null &&
        library.revisionsFor(preview.recipeId).isEmpty;
  } else {
    final base = (feedback['recipe_snapshot'] as Map)['recipe'] as Map;
    final revisionRequest = feedback['revision_request'] as Map;
    matches =
        preview.recipeId == base['id'] &&
        preview.parentRevision == base['revision'] &&
        preview.revision == revisionRequest['next_revision'] &&
        library.revisionFor(preview.recipeId, preview.parentRevision!) !=
            null &&
        library.revisionFor(preview.recipeId, preview.revision) == null;
  }
  if (matches) return preparation;
  library.cancelPreparedImport(preview);
  return const RecipeImportPreparation(
    status: RecipeImportPreparationStatus.failed,
    message: '生成したレシピのID・Version・改善元が依頼と一致しません。保存していません。',
  );
}
