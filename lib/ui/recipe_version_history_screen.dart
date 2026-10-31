import 'recipe_sharing.dart';

import 'package:flutter/material.dart';

import '../application/recipe_library_controller.dart';
import '../domain/recipe_document.dart';
import 'feedback_screen.dart';
import 'recipe_preview_content.dart';
import 'recipe_revision_navigator.dart';
import 'recipe_theme.dart';

class RecipeVersionHistoryScreen extends StatefulWidget {
  const RecipeVersionHistoryScreen({
    required this.recipeId,
    required this.controller,
    this.initialRevision,
    super.key,
  });
  final String recipeId;
  final RecipeLibraryController controller;
  final int? initialRevision;
  @override
  State<RecipeVersionHistoryScreen> createState() =>
      _RecipeVersionHistoryScreenState();
}

class _RecipeVersionHistoryScreenState
    extends State<RecipeVersionHistoryScreen> {
  int? _displayRevision, _comparisonRevision, _savingRevision;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final revisions = widget.controller.revisionsFor(widget.recipeId);
      if (revisions.isEmpty) {
        return Scaffold(
          appBar: AppBar(title: const Text('バージョン履歴')),
          body: const Center(child: Text('バージョン履歴が見つかりません。')),
        );
      }
      final active =
          widget.controller.activeRecipeFor(widget.recipeId) ?? revisions.first;
      // Capture once: browsing and activating never silently move the baseline.
      _comparisonRevision ??= active.revision;
      _displayRevision ??= widget.initialRevision ?? active.revision;
      final displayed =
          widget.controller.revisionFor(widget.recipeId, _displayRevision!) ??
          active;
      final baseline =
          widget.controller.revisionFor(
            widget.recipeId,
            _comparisonRevision!,
          ) ??
          active;
      final isActive = widget.controller.isActiveRevision(
        displayed.id,
        displayed.revision,
      );
      return Scaffold(
        appBar: AppBar(
          title: const Text('バージョン履歴'),
          actions: [
            RecipeShareMenu(
              key: const Key('share_history_recipe'),
              recipe: displayed,
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: DropdownButtonFormField<int>(
                  key: const Key('history_comparison_base'),
                  initialValue: baseline.revision,
                  isExpanded: true,
                  itemHeight: null,
                  decoration: const InputDecoration(labelText: '比較元のバージョン'),
                  style: RecipeTheme.readingNote,
                  items: [
                    for (final recipe in revisions)
                      DropdownMenuItem<int>(
                        value: recipe.revision,
                        child: Text(
                          'バージョン ${recipe.revision}${widget.controller.isActiveRevision(recipe.id, recipe.revision) ? '（使用中）' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _savingRevision != null
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _comparisonRevision = value);
                          }
                        },
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'スワイプしても比較元は変わりません',
                  style: RecipeTheme.readingNote,
                ),
              ),
              Expanded(
                child: RecipeRevisionNavigator(
                  revisions: revisions.map((recipe) => recipe.revision).toList()
                    ..sort(),
                  current: displayed.revision,
                  enabled: _savingRevision == null,
                  onChanged: (value) =>
                      setState(() => _displayRevision = value),
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      textTheme: Theme.of(context).textTheme
                          .copyWith(bodyMedium: RecipeTheme.readingBody),
                    ),
                    child: ListView(
                      key: ValueKey(
                        'history-${displayed.revision}-${baseline.revision}',
                      ),
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (isActive) const Chip(label: Text('使用中のバージョン')),
                            if (widget.controller.isLatestRevision(
                              displayed.id,
                              displayed.revision,
                            ))
                              const Chip(label: Text('最新のバージョン')),
                          ],
                        ),
                        RecipePreviewContent(
                          key: Key('recipe_revision_${displayed.revision}'),
                          preview: RecipeImportPreview.forDisplay(displayed),
                          titleKey: const Key('history_recipe_title'),
                          before: RecipeImportPreview.forDisplay(baseline),
                          historyComparison: true,
                          saved: true,
                        ),
                        OutlinedButton.icon(
                          key: Key('recreate_revision_${displayed.revision}'),
                          onPressed: _savingRevision != null
                              ? null
                              : () => openRecipeAdjustment(
                                  context,
                                  recipe: displayed,
                                  library: widget.controller,
                                ),
                          icon: const Icon(Icons.refresh),
                          label: const Text('このバージョンを調整'),
                        ),
                        OutlinedButton.icon(
                          key: Key('improve_revision_${displayed.revision}'),
                          onPressed: _savingRevision != null
                              ? null
                              : () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => FeedbackScreen(
                                      recipeId: displayed.id,
                                      controller: widget.controller,
                                      initialImprovementRevision:
                                          displayed.revision,
                                    ),
                                  ),
                                ),
                          icon: const Icon(Icons.auto_fix_high_outlined),
                          label: const Text('調理結果から改善'),
                        ),
                        const SizedBox(height: 8),
                        FilledButton(
                          key: Key('activate_revision_${displayed.revision}'),
                          onPressed: isActive || _savingRevision != null
                              ? null
                              : () => _activate(displayed),
                          child: Text(
                            isActive
                                ? '今後使うレシピとして選択中'
                                : _savingRevision != null
                                ? '保存中…'
                                : '今後使うレシピにする',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Future<void> _activate(RecipeDocument revision) async {
    if (_savingRevision != null) return;
    setState(() => _savingRevision = revision.revision);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('バージョン ${revision.revision}を今後使いますか？'),
        content: const Text(
          '次回の通常表示と「最初から」の調理で使います。過去のバージョンと調理途中の記録、比較元の選択は変わりません。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            key: Key('confirm_activate_revision_${revision.revision}'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('今後使う'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true) {
      setState(() => _savingRevision = null);
      return;
    }
    final result = await widget.controller.setActiveRevision(
      revision.id,
      revision.revision,
    );
    if (!mounted) return;
    setState(() => _savingRevision = null);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(result.message)));
  }
}
