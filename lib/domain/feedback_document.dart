import 'package:collection/collection.dart';

import 'feedback_validator.dart';
import 'recipe_document.dart';
import 'session_assessment.dart';

/// Builds a self-contained Feedback v2 document from an immutable cook record.
/// The selected improvement revision may differ from the cooked revision.
class FeedbackDocumentBuilder {
  const FeedbackDocumentBuilder(this.validator);

  final FeedbackValidator validator;

  Map<String, dynamic> build({
    required Map<String, dynamic> completedSession,
    required RecipeDocument improvementRecipe,
    required Iterable<RecipeDocument> knownRevisions,
    required String goal,
    required bool preserveSuccessfulParts,
    String notes = '',
  }) {
    final assessmentRaw = completedSession['assessment'];
    if (assessmentRaw is! Map<String, dynamic>) {
      throw const FormatException('この調理記録には評価が保存されていません。');
    }
    final assessment = SessionAssessment.fromJson(assessmentRaw);
    final source = FeedbackCookingSource.fromStoredSession(completedSession);
    if (goal.trim().isEmpty || improvementRecipe.id != source.recipeId) {
      throw const FormatException('改善対象のRecipeまたは依頼内容が正しくありません。');
    }
    final revisions = knownRevisions.toList();
    if (revisions.isEmpty ||
        revisions.any((recipe) => recipe.id != source.recipeId) ||
        !revisions.any(
          (recipe) =>
              recipe.revision == improvementRecipe.revision &&
              const DeepCollectionEquality().equals(
                recipe.raw,
                improvementRecipe.raw,
              ),
        )) {
      throw const FormatException('改善対象のVersionが保存済み履歴にありません。');
    }
    final nextRevision =
        <int>[
          source.recipeRevision,
          for (final recipe in revisions) recipe.revision,
        ].reduce((a, b) => a > b ? a : b) +
        1;
    final document = <String, dynamic>{
      'schema_version': '2.0.0',
      'type': 'recipe_feedback',
      'recipe_snapshot': RecipeDocument.copyJson(improvementRecipe.raw),
      'cook_session': {
        'id': completedSession['session_id'],
        'recipe_id': source.recipeId,
        'recipe_revision': source.recipeRevision,
        'recipe_snapshot': source.recipeSnapshot,
        'cooking_context': source.cookingContext.toJson(),
        'cooked_at': completedSession['completed_at'],
        'actual_time_minutes': assessment.actualTimeMinutes,
        'difficulty': {
          'score': assessment.difficultyScore,
          'comment': assessment.difficultyComment,
        },
        'issues': assessment.issues,
        'changes_made': assessment.changesMade,
      },
      'evaluation': assessment.toJson()['evaluation'],
      'revision_request': {
        'preserve_successful_parts': preserveSuccessfulParts,
        'goal': goal.trim(),
        'next_revision': nextRevision,
        if (notes.trim().isNotEmpty) 'notes': notes.trim(),
      },
    };
    return validator.validateDocument(document);
  }
}
