import 'package:flutter/material.dart';

import '../application/recipe_library_controller.dart';
import '../domain/recipe_comparison.dart';
import 'recipe_changes_card.dart';
import 'recipe_compared_text.dart';
import 'recipe_theme.dart';

class RecipeComparedSteps extends StatelessWidget {
  const RecipeComparedSteps({
    required this.preview,
    this.comparison,
    this.targetServings,
    super.key,
  });
  final RecipeImportPreview preview;
  final RecipeComparison? comparison;
  final int? targetServings;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (index, step)
          in preview.comparisonSteps(targetServings: targetServings).indexed)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RecipeComparedText(
                text: '工程 ${index + 1}: ${step.title}',
                before: comparison?.changeFor('step:${step.id}')?.before,
                compared: comparison?.changeFor('step:${step.id}') != null,
                style: RecipeTheme.readingHeading,
              ),
              const SizedBox(height: 6),
              for (final field in step.fields)
                if (field.text.isNotEmpty)
                  RecipeComparedText(
                    key: ValueKey('step_text_${field.key}'),
                    text: field.text,
                    prefix: field.label.isEmpty ? '' : '${field.label}: ',
                    before: comparison?.changeFor(field.key)?.before,
                    compared:
                        comparison?.changeFor(field.key)?.after == field.text &&
                        (targetServings == null ||
                            targetServings == preview.servings),
                  ),
              if (comparison != null &&
                  comparison!.changes.any(
                    (change) =>
                        change.contentKey?.endsWith(':${step.id}') == true,
                  ))
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: ValueKey('step_changes_${step.id}'),
                    onPressed: () => showRecipeChangeDetails(
                      context,
                      comparison!,
                      comparison!.changes
                          .where(
                            (change) =>
                                change.contentKey?.endsWith(':${step.id}') ==
                                true,
                          )
                          .toList(),
                      title: '工程 ${index + 1}の変更点',
                      showBefore: true,
                    ),
                    child: const Text('変更前を見る'),
                  ),
                ),
            ],
          ),
        ),
    ],
  );
}
