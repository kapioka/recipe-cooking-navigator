import 'package:flutter/material.dart';

import '../application/recipe_library_controller.dart';
import 'recipe_section.dart';
import 'recipe_theme.dart';
import 'recipe_changes_card.dart';
import 'recipe_difficulty_meter.dart';
import '../domain/recipe_comparison.dart';
import 'recipe_compared_text.dart';
import 'recipe_compared_steps.dart';

class RecipePreviewContent extends StatefulWidget {
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
  State<RecipePreviewContent> createState() => _RecipePreviewContentState();
}

class _RecipePreviewContentState extends State<RecipePreviewContent> {
  final _sections = {
    for (final section in ['概要', '材料', '器具', '事前準備', '全体工程', '調理の工程', '調整・注意'])
      section: GlobalKey(),
  };
  RecipeImportPreview get preview => widget.preview;
  bool get historyComparison => widget.historyComparison;
  Widget _line(String text, String key, RecipeComparison? comparison) {
    final change = comparison?.changeFor(key);
    String? displayed(String? value) => key.startsWith('amount:')
        ? value?.split('\n用途:').first
        : key == 'serving_adjustment'
        ? value?.split('\n').skip(1).join('\n')
        : value;
    final after = displayed(change?.after);
    final before = displayed(change?.before);
    return RecipeComparedText(
      text: text,
      before: before,
      compared: after == text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final comparison = widget.before == null
        ? null
        : preview.compareWith(widget.before!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RecipeSection(
          key: _sections['概要'],
          color: RecipeTheme.sage,
          children: [
            Semantics(
              header: true,
              liveRegion: true,
              child: Text(
                preview.title,
                key: widget.titleKey,
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
            Text(widget.saved ? 'このレシピは保存済みです' : 'まだ保存されていません'),
          ],
        ),
        if (comparison != null)
          RecipeChangesCard(
            comparison: comparison,
            browsing: historyComparison,
            onSectionSelected: (section) {
              final target = _sections[section]?.currentContext;
              if (target != null) {
                Scrollable.ensureVisible(
                  target,
                  alignment: 0.05,
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 250),
                );
              } else {
                showRecipeChangeDetails(
                  context,
                  comparison,
                  comparison.changes
                      .where((change) => change.section == section)
                      .toList(),
                  title: section,
                );
              }
            },
          ),
        RecipeSection(
          key: _sections['材料'],
          title: '材料と分量',
          icon: Icons.restaurant_outlined,
          children: [
            for (final (index, line) in preview.ingredientDetails.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: _line(
                  line,
                  'amount:${preview.amountIds[index]}',
                  comparison,
                ),
              ),
          ],
        ),
        if (historyComparison) ...[
          RecipeSection(
            key: _sections['器具'],
            title: '器具',
            icon: Icons.kitchen_outlined,
            children: [
              for (final (index, line) in preview.utensilDetails.indexed)
                _line(line, 'utensil:${preview.utensilIds[index]}', comparison),
            ],
          ),
          RecipeSection(
            key: _sections['事前準備'],
            title: '事前準備',
            icon: Icons.checklist,
            children: [
              for (final (index, line) in preview.preparationDetails.indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: _line(
                    '準備 ${index + 1}: $line',
                    'prep:${preview.preparationIds[index]}',
                    comparison,
                  ),
                ),
            ],
          ),
          RecipeSection(
            key: _sections['全体工程'],
            title: '全体工程',
            icon: Icons.route_outlined,
            children: [
              for (final (index, line) in preview.overviewDetails.indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: _line(line, 'overview:$index', comparison),
                ),
            ],
          ),
        ],
        RecipeSection(
          key: _sections['調理の工程'],
          title: '調理の工程',
          icon: Icons.format_list_numbered,
          children: [
            if (comparison != null || historyComparison)
              RecipeComparedSteps(preview: preview, comparison: comparison)
            else
              for (final (index, line) in preview.stepDetails.indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('${index + 1}. $line'),
                ),
          ],
        ),
        if (preview.adjustmentDetails.isNotEmpty)
          RecipeSection(
            key: _sections['調整・注意'],
            title: 'コツ・失敗対策',
            icon: Icons.tune,
            children: [
              for (final (index, line) in preview.adjustmentDetails.indexed)
                _line(line, 'adjustment:$index', comparison),
            ],
          ),
        if (preview.notices.isNotEmpty)
          RecipeSection(
            key: preview.adjustmentDetails.isNotEmpty
                ? null
                : _sections['調整・注意'],
            title: '調理・保存の注意',
            icon: Icons.info_outline,
            color: RecipeTheme.warningSurface,
            children: [
              for (final (index, line) in preview.notices.indexed)
                _line(line, preview.noticeKeys[index], comparison),
            ],
          ),
      ],
    );
  }
}
