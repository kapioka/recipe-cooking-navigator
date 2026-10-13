import 'package:flutter/material.dart';

import '../domain/recipe_comparison.dart';
import 'recipe_section.dart';
import 'recipe_theme.dart';

class RecipeChangesCard extends StatelessWidget {
  const RecipeChangesCard({required this.comparison, super.key});
  final RecipeComparison comparison;
  @override
  Widget build(BuildContext context) => RecipeSection(
    title: '改善前後の比較',
    icon: Icons.compare_arrows,
    titleStyle: RecipeTheme.readingHeading,
    children: [
      Text(
        'バージョン ${comparison.beforeRevision} → ${comparison.afterRevision}',
        style: RecipeTheme.readingNote,
      ),
      const SizedBox(height: 8),
      if (comparison.changes.isEmpty)
        const Text('調理内容に変更はありません。バージョン番号やAIの変更説明は比較に含めていません。')
      else
        ExpansionTile(
          key: const Key('recipe_content_changes'),
          tilePadding: EdgeInsets.zero,
          title: Text('変更点（${comparison.changes.length}項目）'),
          subtitle: const Text('色付きが変更後の内容です。変更前も確認できます。'),
          children: [
            for (final change in comparison.changes)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${change.kind} · ${change.section} / ${change.label}',
                      style: RecipeTheme.readingHeading,
                    ),
                    if (change.before != null) ...[
                      const SizedBox(height: 8),
                      const Text('変更前', style: RecipeTheme.readingNote),
                      SelectableText(
                        change.before!,
                        style: RecipeTheme.readingBody,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: RecipeTheme.sage,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            change.after == null ? '変更後 · 削除されました' : '変更後',
                            style: RecipeTheme.readingNote,
                          ),
                          if (change.after != null)
                            SelectableText(
                              change.after!,
                              style: RecipeTheme.readingBody.copyWith(
                                fontWeight: FontWeight.w600,
                                color: RecipeTheme.forest,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
    ],
  );
}
