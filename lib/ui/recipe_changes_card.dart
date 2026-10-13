import 'package:flutter/material.dart';

import '../domain/recipe_comparison.dart';
import '../domain/recipe_text_diff.dart';
import 'recipe_compared_text.dart';
import 'recipe_section.dart';
import 'recipe_theme.dart';

class RecipeChangesCard extends StatelessWidget {
  const RecipeChangesCard({
    required this.comparison,
    this.browsing = false,
    this.onSectionSelected,
    super.key,
  });
  final RecipeComparison comparison;
  final bool browsing;
  final ValueChanged<String>? onSectionSelected;

  @override
  Widget build(BuildContext context) {
    final groups = <String, int>{};
    for (final change in comparison.changes) {
      groups.update(change.section, (count) => count + 1, ifAbsent: () => 1);
    }
    return RecipeSection(
      title: browsing ? '比較元との違い' : '改善前後の比較',
      icon: Icons.compare_arrows,
      titleStyle: RecipeTheme.readingHeading,
      children: [
        Text(
          '比較元: バージョン ${comparison.beforeRevision} → 表示中: ${comparison.afterRevision}',
          style: RecipeTheme.readingNote,
        ),
        if (comparison.changes.isEmpty)
          const Text('調理内容に変更はありません。', style: RecipeTheme.readingNote)
        else ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final group in groups.entries)
                ActionChip(
                  key: ValueKey('change_section_${group.key}'),
                  label: Text(
                    '${group.key == '調理の工程'
                        ? '工程'
                        : group.key == '調整・注意'
                        ? '注意'
                        : group.key} ${group.value}件',
                  ),
                  onPressed: () {
                    if (onSectionSelected != null) {
                      onSectionSelected!(group.key);
                    } else {
                      showRecipeChangeDetails(
                        context,
                        comparison,
                        comparison.changes
                            .where((change) => change.section == group.key)
                            .toList(),
                        title: group.key,
                      );
                    }
                  },
                ),
            ],
          ),
          const Text(
            '緑＝表示中・淡い赤＝比較元。基準人数同士で比較。',
            style: RecipeTheme.readingNote,
          ),
          ExpansionTile(
            key: const Key('recipe_content_changes'),
            tilePadding: EdgeInsets.zero,
            title: Text('変更点（${comparison.changes.length}項目）'),
            children: [
              for (final change in comparison.changes)
                ListTile(
                  key: ValueKey('compact_change_${change.contentKey}'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    '${change.kind} · ${change.label}',
                    style: RecipeTheme.readingNote,
                  ),
                  subtitle: _CompactValues(change: change),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => showRecipeChangeDetails(context, comparison, [
                    change,
                  ], title: change.label),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _CompactValues extends StatelessWidget {
  const _CompactValues({required this.change});
  final RecipeContentChange change;
  @override
  Widget build(BuildContext context) {
    if (change.after == null) {
      return const Text('削除された内容を見る', style: RecipeTheme.readingNote);
    }
    final diff = RecipeTextDiff(change.before ?? '', change.after!);
    if (change.before != null &&
        !diff.afterFragments.any((part) => part.changed)) {
      return const Text('文章の一部を削除（全文を見る）', style: RecipeTheme.readingNote);
    }
    final before = RecipeTextDiff.excerpt(diff.beforeFragments);
    final after = RecipeTextDiff.excerpt(diff.afterFragments);
    return Text.rich(
      TextSpan(
        children: [
          if (change.before != null) ...[
            TextSpan(
              text: before,
              style: const TextStyle(
                backgroundColor: Color(0xFFF4E4E2),
                color: Color(0xFF793F3B),
              ),
            ),
            const TextSpan(text: ' → '),
          ],
          TextSpan(
            text: after,
            style: const TextStyle(
              backgroundColor: RecipeTheme.sage,
              color: RecipeTheme.forest,
            ),
          ),
        ],
      ),
      style: RecipeTheme.readingNote,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

Future<void> showRecipeChangeDetails(
  BuildContext context,
  RecipeComparison comparison,
  List<RecipeContentChange> changes, {
  required String title,
  bool showBefore = false,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (context) => FractionallySizedBox(
    heightFactor: 0.85,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: RecipeTheme.readingHeading,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                key: const Key('close_change_details'),
                tooltip: '変更点を閉じる',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              for (final change in changes)
                RecipeSection(
                  title: '${change.kind} · ${change.label}',
                  children: [
                    if (change.after != null) ...[
                      Text(
                        '表示中 · バージョン ${comparison.afterRevision}',
                        style: RecipeTheme.readingNote,
                      ),
                      RecipeComparedText(
                        text: change.after!,
                        before: change.before,
                        compared: true,
                      ),
                    ] else
                      const Text('表示中にはありません', style: RecipeTheme.readingNote),
                    if (change.before != null)
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                        initiallyExpanded: showBefore || change.after == null,
                        title: Text(
                          change.after == null ? '削除された内容' : '変更前を見る',
                        ),
                        children: [
                          Text(
                            '比較元 · バージョン ${comparison.beforeRevision}',
                            style: RecipeTheme.readingNote,
                          ),
                          RecipeComparedText(
                            text: change.before!,
                            before: change.after,
                            compared: true,
                            baseline: true,
                          ),
                        ],
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    ),
  ),
);
