import 'package:flutter/material.dart';

import '../application/recipe_library_controller.dart';
import 'recipe_section.dart';
import 'recipe_theme.dart';
import 'recipe_changes_card.dart';
import 'recipe_difficulty_meter.dart';

class RecipePreviewContent extends StatelessWidget {
  const RecipePreviewContent({
    required this.preview,
    this.titleKey,
    this.saved = false,
    this.before,
    this.historyComparison = false,
    super.key,
  });
  final RecipeImportPreview preview;
  final Key? titleKey;
  final bool saved;
  final RecipeImportPreview? before;
  final bool historyComparison;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      RecipeSection(
        color: RecipeTheme.sage,
        children: [
          Semantics(
            header: true,
            liveRegion: true,
            child: Text(
              preview.title,
              key: titleKey,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          const SizedBox(height: 8),
          Text('${preview.servings}人分・約${preview.totalTimeMinutes}分'),
          if (historyComparison) ...[
            const SizedBox(height: 8),
            RecipeDifficultyMeter(difficulty: preview.estimatedDifficulty),
          ],
          if (preview.parentRevision != null)
            Text(
              'バージョン ${preview.parentRevision}から改善したバージョン ${preview.revision}',
            ),
          const SizedBox(height: 8),
          Text(saved ? 'このレシピは保存済みです' : 'まだ保存されていません'),
        ],
      ),
      if (before != null)
        RecipeChangesCard(
          comparison: preview.compareWith(before!),
          browsing: historyComparison,
        ),
      RecipeSection(
        title: '材料と分量',
        icon: Icons.restaurant_outlined,
        children: [
          for (final line in preview.ingredientDetails)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(line),
            ),
        ],
      ),
      if (historyComparison) ...[
        RecipeSection(
          title: '器具',
          icon: Icons.kitchen_outlined,
          children: [for (final line in preview.utensilDetails) Text(line)],
        ),
        RecipeSection(
          title: '事前準備',
          icon: Icons.checklist,
          children: [
            for (final (index, line) in preview.preparationDetails.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text('${index + 1}. $line'),
              ),
          ],
        ),
        RecipeSection(
          title: '全体工程',
          icon: Icons.route_outlined,
          children: [
            for (final (index, line) in preview.overviewDetails.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text('${index + 1}. $line'),
              ),
          ],
        ),
      ],
      RecipeSection(
        title: '調理の工程',
        icon: Icons.format_list_numbered,
        children: [
          for (final (index, line)
              in (historyComparison
                      ? preview.completeStepDetails
                      : preview.stepDetails)
                  .indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('${index + 1}. $line'),
            ),
        ],
      ),
      if (historyComparison && preview.adjustmentDetails.isNotEmpty)
        RecipeSection(
          title: '調整のヒント',
          icon: Icons.tune,
          children: [for (final line in preview.adjustmentDetails) Text(line)],
        ),
      if (preview.notices.isNotEmpty)
        RecipeSection(
          title: '調理・保存の注意',
          icon: Icons.info_outline,
          color: RecipeTheme.warningSurface,
          children: [for (final line in preview.notices) Text(line)],
        ),
    ],
  );
}
