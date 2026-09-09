import 'package:flutter/material.dart';

import '../application/recipe_library_controller.dart';
import '../domain/recipe_document.dart';

class RecipeVersionHistoryScreen extends StatefulWidget {
  const RecipeVersionHistoryScreen({
    required this.recipeId,
    required this.controller,
    super.key,
  });

  final String recipeId;
  final RecipeLibraryController controller;

  @override
  State<RecipeVersionHistoryScreen> createState() =>
      _RecipeVersionHistoryScreenState();
}

class _RecipeVersionHistoryScreenState
    extends State<RecipeVersionHistoryScreen> {
  int? _savingRevision;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final revisions = widget.controller.revisionsFor(widget.recipeId);
        final latest = widget.controller.latestRecipeFor(widget.recipeId);
        return Scaffold(
          appBar: AppBar(title: const Text('Version履歴')),
          body: revisions.isEmpty
              ? const Center(child: Text('Version履歴が見つかりません。'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    Text(
                      latest?.title ?? revisions.first.title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'activeは通常表示と「最初から」の調理に使うVersionです。'
                      '切り替えても、保存済みの調理途中位置や過去Versionは変更しません。',
                    ),
                    const SizedBox(height: 16),
                    for (final revision in revisions)
                      _VersionCard(
                        revision: revision,
                        isActive: widget.controller.isActiveRevision(
                          revision.id,
                          revision.revision,
                        ),
                        isLatest: widget.controller.isLatestRevision(
                          revision.id,
                          revision.revision,
                        ),
                        isBusy: _savingRevision != null,
                        isSaving: _savingRevision == revision.revision,
                        onActivate: () => _activate(revision),
                      ),
                  ],
                ),
        );
      },
    );
  }

  Future<void> _activate(RecipeDocument revision) async {
    if (_savingRevision != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Version ${revision.revision}をactiveにしますか？'),
        content: const Text(
          '次回の通常表示と「最初から」の調理で使います。'
          '現在の調理途中位置は別に保持され、変更されません。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            key: Key('confirm_activate_revision_${revision.revision}'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('activeにする'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _savingRevision = revision.revision);
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

class _VersionCard extends StatelessWidget {
  const _VersionCard({
    required this.revision,
    required this.isActive,
    required this.isLatest,
    required this.isBusy,
    required this.isSaving,
    required this.onActivate,
  });

  final RecipeDocument revision;
  final bool isActive;
  final bool isLatest;
  final bool isBusy;
  final bool isSaving;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final parent = revision.parentRevision;
    return Card(
      key: Key('recipe_revision_${revision.revision}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Version ${revision.revision}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (isLatest) const Chip(label: Text('latest')),
                if (isActive) const Chip(label: Text('active')),
              ],
            ),
            const SizedBox(height: 4),
            Text(revision.title),
            const SizedBox(height: 4),
            Text(
              '${revision.servings}人分 ・ ${revision.totalTimeMinutes}分 ・ '
              'AI想定難易度 ${revision.estimatedDifficulty}',
            ),
            const SizedBox(height: 4),
            Text(parent == null ? '最初のVersion' : 'Version $parentから派生'),
            if (!isActive) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  key: Key('activate_revision_${revision.revision}'),
                  onPressed: isBusy ? null : onActivate,
                  child: Text(isSaving ? '保存中…' : 'activeにする'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
