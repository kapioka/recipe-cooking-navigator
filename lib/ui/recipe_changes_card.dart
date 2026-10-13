import 'package:flutter/material.dart';

import '../domain/recipe_comparison.dart';
import 'recipe_section.dart';
import 'recipe_theme.dart';

class RecipeChangesCard extends StatelessWidget {
  const RecipeChangesCard({
    required this.comparison,
    this.browsing = false,
    super.key,
  });
  final RecipeComparison comparison;
  final bool browsing;
  @override
  Widget build(BuildContext context) => RecipeSection(
    title: browsing ? '比較元との違い' : '改善前後の比較',
    icon: Icons.compare_arrows,
    titleStyle: RecipeTheme.readingHeading,
    children: [
      Text(
        browsing
            ? '比較元: バージョン ${comparison.beforeRevision}\n表示中: バージョン ${comparison.afterRevision}'
            : 'バージョン ${comparison.beforeRevision} → ${comparison.afterRevision}',
        style: RecipeTheme.readingNote,
      ),
      const SizedBox(height: 8),
      if (comparison.changes.isEmpty)
        Text(
          browsing
              ? '比較元と調理内容は同じです。バージョン番号やAIの変更説明は比較に含めていません。'
              : '調理内容に変更はありません。バージョン番号やAIの変更説明は比較に含めていません。',
        )
      else
        ExpansionTile(
          key: const Key('recipe_content_changes'),
          tilePadding: EdgeInsets.zero,
          title: Text('変更点（${comparison.changes.length}項目）'),
          subtitle: Text(
            browsing
                ? '緑は表示中、淡い赤は比較元の内容です。新旧の順番によらず同じ意味で表示します。'
                : '色付きが変更後の内容です。変更前も確認できます。',
          ),
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
                      Container(
                        padding: browsing
                            ? const EdgeInsets.all(12)
                            : EdgeInsets.zero,
                        decoration: browsing
                            ? BoxDecoration(
                                color: const Color(0xFFF4E4E2),
                                borderRadius: BorderRadius.circular(16),
                              )
                            : null,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              browsing
                                  ? '比較元 · バージョン ${comparison.beforeRevision}'
                                  : '変更前',
                              style: RecipeTheme.readingNote,
                            ),
                            SelectableText(
                              change.before!,
                              style: RecipeTheme.readingBody,
                            ),
                          ],
                        ),
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
                            browsing
                                ? change.after == null
                                      ? '表示中にはありません'
                                      : '表示中 · バージョン ${comparison.afterRevision}'
                                : change.after == null
                                ? '変更後 · 削除されました'
                                : '変更後',
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
