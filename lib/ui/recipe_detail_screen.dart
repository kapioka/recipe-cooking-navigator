import 'package:flutter/material.dart';

import '../application/recipe_library_controller.dart';
import '../domain/recipe_document.dart';
import 'cooking_entry.dart';
import 'preparation_checklist.dart';
import 'recipe_sharing.dart';
import 'feedback_screen.dart';
import 'recipe_section.dart';
import 'recipe_heading.dart';
import 'recipe_theme.dart';
import 'recipe_difficulty_meter.dart';
import 'recipe_changes_card.dart';
import 'recipe_revision_navigator.dart';
import 'recipe_version_history_screen.dart';
import '../domain/recipe_comparison.dart';
import 'recipe_compared_text.dart';
import 'recipe_compared_steps.dart';

class RecipeDetailScreen extends StatefulWidget {
  const RecipeDetailScreen({
    required this.recipe,
    required this.controller,
    this.showExactRevision = false,
    super.key,
  });

  final RecipeDocument recipe;
  final RecipeLibraryController controller;
  final bool showExactRevision;

  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends State<RecipeDetailScreen> {
  late int selectedServings = widget.recipe.servings;
  late String activeIdentity = '${widget.recipe.id}:${widget.recipe.revision}';
  int preparationVersion = 0;
  bool preparationSaving = false;
  int? _browsingRevision;
  bool _activatingRevision = false;
  bool _showDetailedSteps = false;
  final _changeSections = {
    for (final section in ['概要', '材料', '器具', '事前準備', '全体工程', '調理の工程', '調整・注意'])
      section: GlobalKey(),
  };

  RecipeLibraryController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final activeRecipe =
            (_browsingRevision == null
                ? null
                : controller.revisionFor(
                    widget.recipe.id,
                    _browsingRevision!,
                  )) ??
            (widget.showExactRevision
                ? widget.recipe
                : controller.activeRecipeFor(widget.recipe.id) ??
                      widget.recipe);
        final identity = '${activeRecipe.id}:${activeRecipe.revision}';
        if (identity != activeIdentity) {
          activeIdentity = identity;
          selectedServings = activeRecipe.servings;
        }
        final cookingContext = activeRecipe.contextFor(selectedServings);
        final ingredientSummaries = activeRecipe.ingredientSummaries(
          cookingContext,
        );
        final latestRecipe = controller.latestRecipeFor(widget.recipe.id);
        final revisions = controller.revisionsFor(widget.recipe.id);
        final tags = controller.tagsFor(activeRecipe.id);
        final utensils = activeRecipe.recipeData['utensils'] as List;
        final preparation = activeRecipe.recipeData['preparation'] as List;
        final parent = activeRecipe.parentRevision == null
            ? null
            : controller.revisionFor(
                activeRecipe.id,
                activeRecipe.parentRevision!,
              );
        final preview = RecipeImportPreview.forDisplay(activeRecipe);
        final comparison = parent == null
            ? null
            : preview.compareWith(RecipeImportPreview.forDisplay(parent));
        final previousQuantities = {
          if (parent != null)
            for (final ingredient in parent.ingredientSummaries(
              parent.contextFor(parent.servings),
            ))
              ingredient.id: ingredient.quantity,
        };
        return Scaffold(
          appBar: AppBar(
            title: const Text('レシピ詳細'),
            actions: [
              RecipeShareMenu(
                key: const Key('share_recipe'),
                recipe: activeRecipe,
                onAdjust: () => openRecipeAdjustment(
                  context,
                  recipe: activeRecipe,
                  library: controller,
                ),
              ),
              IconButton(
                key: const Key('edit_recipe_tags_button'),
                tooltip: 'タグを編集',
                onPressed: () => _editTags(context),
                icon: const Icon(Icons.sell_outlined),
              ),
            ],
          ),
          body: RecipeRevisionNavigator(
            revisions: revisions.map((recipe) => recipe.revision).toList()
              ..sort(),
            current: activeRecipe.revision,
            enabled: !_activatingRevision && !preparationSaving,
            onChanged: (revision) =>
                setState(() => _browsingRevision = revision),
            child: Theme(
              data: Theme.of(context).copyWith(
                textTheme: Theme.of(context).textTheme.copyWith(
                  bodyMedium: RecipeTheme.readingBody,
                  bodyLarge: RecipeTheme.readingBody,
                ),
              ),
              child: ListView(
                key: ValueKey('detail-$identity'),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      KeyedSubtree(
                        key: _changeSections['概要'],
                        child: RecipeSection(
                          key: const Key('detail_recipe_summary'),
                          children: [
                            RecipeHeading(
                              recipe: activeRecipe,
                              controller: controller,
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 16,
                              runSpacing: 8,
                              children: [
                                Text(
                                  '$selectedServings人分',
                                  key: const Key('selected_servings_chip'),
                                  style: RecipeTheme.readingNote,
                                ),
                                Text(
                                  '調理時間目安 ${activeRecipe.totalTimeMinutes}分',
                                  style: RecipeTheme.readingNote,
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            RecipeDifficultyMeter(
                              difficulty: activeRecipe.estimatedDifficulty,
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: RecipeTheme.sage,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Wrap(
                                spacing: 12,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    controller.isActiveRevision(
                                          activeRecipe.id,
                                          activeRecipe.revision,
                                        )
                                        ? '使用中のバージョン ${activeRecipe.revision}'
                                        : '表示中のバージョン ${activeRecipe.revision}',
                                    key: const Key(
                                      'active_recipe_version_chip',
                                    ),
                                    style: RecipeTheme.readingNote,
                                  ),
                                  if (latestRecipe != null &&
                                      latestRecipe.revision !=
                                          activeRecipe.revision)
                                    Text(
                                      '最新のバージョン ${latestRecipe.revision}',
                                      style: RecipeTheme.readingNote,
                                    ),
                                  TextButton.icon(
                                    key: const Key('open_version_history'),
                                    onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            RecipeVersionHistoryScreen(
                                              recipeId: activeRecipe.id,
                                              controller: controller,
                                              initialRevision:
                                                  activeRecipe.revision,
                                            ),
                                      ),
                                    ),
                                    icon: const Icon(Icons.history, size: 18),
                                    label: Text('履歴（${revisions.length}件）'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton.icon(
                        key: const Key('use_displayed_recipe'),
                        onPressed:
                            _activatingRevision ||
                                controller.isActiveRevision(
                                  activeRecipe.id,
                                  activeRecipe.revision,
                                )
                            ? null
                            : () => _useDisplayedRecipe(activeRecipe),
                        icon: const Icon(Icons.check_circle_outline),
                        label: Text(
                          controller.isActiveRevision(
                                activeRecipe.id,
                                activeRecipe.revision,
                              )
                              ? '今後使うレシピとして選択中'
                              : '今後使うレシピにする',
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (comparison != null)
                        RecipeChangesCard(
                          comparison: comparison,
                          onSectionSelected: (section) =>
                              _jumpToChange(section, comparison),
                        ),
                      if (activeRecipe.parentRevision != null && parent == null)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 16),
                          child: Text('改善元が端末にないため、変更点を比較できません。'),
                        ),
                      ExpansionTile(
                        key: ValueKey('creation-conditions-$identity'),
                        title: const Text('このレシピを作った条件'),
                        childrenPadding: const EdgeInsets.all(16),
                        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SelectableText(
                            controller.creationConditionsFor(
                                  activeRecipe.id,
                                  activeRecipe.revision,
                                ) ??
                                controller.creationRecordError ??
                                'このバージョンの作成条件は記録されていません。保存されたレシピデータを表示しています。',
                          ),
                        ],
                      ),
                      RecipeSection(
                        key: _changeSections['材料'],
                        title: '材料',
                        icon: Icons.restaurant_outlined,
                        titleStyle: RecipeTheme.readingHeading,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: RecipeTheme.cream,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  '調理する人数',
                                  style: RecipeTheme.readingNote,
                                ),
                                const SizedBox(height: 4),
                                Semantics(
                                  label: '調理人数、現在$selectedServings人分',
                                  child: Row(
                                    children: [
                                      IconButton.outlined(
                                        key: const Key('decrease_servings'),
                                        tooltip: '人数を1人減らす',
                                        onPressed:
                                            selectedServings >
                                                activeRecipe.minServings
                                            ? () => setState(
                                                () => selectedServings--,
                                              )
                                            : null,
                                        icon: const Icon(Icons.remove),
                                      ),
                                      Expanded(
                                        child: Text(
                                          '$selectedServings 人分',
                                          textAlign: TextAlign.center,
                                          style: RecipeTheme.readingHeading,
                                        ),
                                      ),
                                      IconButton.outlined(
                                        key: const Key('increase_servings'),
                                        tooltip: '人数を1人増やす',
                                        onPressed:
                                            selectedServings <
                                                activeRecipe.maxServings
                                            ? () => setState(
                                                () => selectedServings++,
                                              )
                                            : null,
                                        icon: const Icon(Icons.add),
                                      ),
                                    ],
                                  ),
                                ),
                                Wrap(
                                  alignment: WrapAlignment.spaceBetween,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      '基準 ${activeRecipe.servings}人分',
                                      style: RecipeTheme.readingNote,
                                    ),
                                    TextButton(
                                      key: const Key('reset_servings'),
                                      onPressed:
                                          selectedServings ==
                                              activeRecipe.servings
                                          ? null
                                          : () => setState(
                                              () => selectedServings =
                                                  activeRecipe.servings,
                                            ),
                                      child: const Text('基準人数に戻す'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          for (final ingredient in ingredientSummaries)
                            _DetailQuantityRow(
                              name: ingredient.name,
                              quantity: ingredient.quantity,
                              note: [
                                ingredient.details,
                                ingredient.note,
                              ].whereType<String>().join('\n'),
                              previousQuantity:
                                  previousQuantities[ingredient.id],
                              compared:
                                  parent != null &&
                                  selectedServings == activeRecipe.servings &&
                                  activeRecipe.amounts.any(
                                    (amount) =>
                                        amount.ingredientId == ingredient.id &&
                                        comparison?.changeFor(
                                              'amount:${amount.id}',
                                            ) !=
                                            null,
                                  ),
                            ),
                          const SizedBox(height: 8),
                          Text(
                            activeRecipe.minServings == activeRecipe.maxServings
                                ? 'このレシピは人数変更できません。${activeRecipe.servingAdjustmentNote}'
                                : selectedServings == activeRecipe.servings
                                ? activeRecipe.servingAdjustmentNote
                                : '材料を$selectedServings人分に換算しています。加熱時間・火加減・器具は自動調整されません。\n${activeRecipe.servingAdjustmentNote}',
                            key: const Key('serving_adjustment_note'),
                            style: RecipeTheme.readingNote,
                          ),
                        ],
                      ),
                      if (utensils.isNotEmpty)
                        RecipeSection(
                          key: _changeSections['器具'],
                          title: '器具',
                          icon: Icons.soup_kitchen_outlined,
                          titleStyle: RecipeTheme.readingHeading,
                          children: [
                            for (final utensil in utensils)
                              _DetailQuantityRow(
                                name: utensil['name'] as String,
                                quantity: '${utensil['quantity']}',
                                note: utensil['reuse_note'] == null
                                    ? ''
                                    : activeRecipe
                                          .renderText(
                                            utensil['reuse_note']
                                                as List<dynamic>,
                                            cookingContext,
                                          )
                                          .displayText,
                              ),
                          ],
                        ),
                      if (preparation.isNotEmpty)
                        RecipeSection(
                          key: _changeSections['事前準備'],
                          title: '事前準備',
                          icon: Icons.checklist_outlined,
                          titleStyle: RecipeTheme.readingHeading,
                          children: [
                            PreparationChecklist(
                              key: ValueKey('$identity:$preparationVersion'),
                              recipe: activeRecipe,
                              cookingContext: cookingContext,
                              store: controller.preparationStore,
                              showHeading: false,
                              onBusy: (value) =>
                                  setState(() => preparationSaving = value),
                            ),
                          ],
                        ),
                      RecipeSection(
                        key: _changeSections['全体工程'],
                        title: '全体工程',
                        icon: Icons.format_list_numbered_outlined,
                        titleStyle: RecipeTheme.readingHeading,
                        children: [
                          for (final entry in activeRecipe.overview.indexed)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: RecipeTheme.sage,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '${entry.$1 + 1}',
                                      style: RecipeTheme.readingNote.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: RecipeComparedText(
                                      text: activeRecipe
                                          .renderText(entry.$2, cookingContext)
                                          .displayText,
                                      before: comparison
                                          ?.changeFor('overview:${entry.$1}')
                                          ?.before,
                                      compared:
                                          selectedServings ==
                                              activeRecipe.servings &&
                                          comparison?.changeFor(
                                                'overview:${entry.$1}',
                                              ) !=
                                              null,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      RecipeSection(
                        key: _changeSections['調理の工程'],
                        title: '調理の工程',
                        icon: Icons.restaurant_menu_outlined,
                        titleStyle: RecipeTheme.readingHeading,
                        children: [
                          if (_showDetailedSteps)
                            RecipeComparedSteps(
                              preview: preview,
                              comparison: comparison,
                              targetServings: selectedServings,
                            ),
                          TextButton.icon(
                            key: const Key('toggle_detailed_steps'),
                            onPressed: () => setState(
                              () => _showDetailedSteps = !_showDetailedSteps,
                            ),
                            icon: Icon(
                              _showDetailedSteps
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                            ),
                            label: Text(
                              _showDetailedSteps ? '詳しい工程を閉じる' : '詳しい工程を開く',
                            ),
                          ),
                        ],
                      ),
                      if (preview.adjustmentDetails.isNotEmpty)
                        RecipeSection(
                          key: _changeSections['調整・注意'],
                          title: 'コツ・失敗対策',
                          icon: Icons.tune,
                          children: [
                            for (final (index, line)
                                in preview.adjustmentDetails.indexed)
                              RecipeComparedText(
                                text: line,
                                before: comparison
                                    ?.changeFor('adjustment:$index')
                                    ?.before,
                                compared:
                                    comparison
                                        ?.changeFor('adjustment:$index')
                                        ?.after ==
                                    line,
                              ),
                          ],
                        ),
                      RecipeSection(
                        key: preview.adjustmentDetails.isEmpty
                            ? _changeSections['調整・注意']
                            : null,
                        title: '調理・保存の注意',
                        icon: Icons.info_outline,
                        color: RecipeTheme.warningSurface,
                        children: [
                          for (final (index, line) in preview.notices.indexed)
                            RecipeComparedText(
                              text: line,
                              before: comparison
                                  ?.changeFor(preview.noticeKeys[index])
                                  ?.before,
                              compared:
                                  comparison
                                      ?.changeFor(preview.noticeKeys[index])
                                      ?.after ==
                                  line,
                            ),
                        ],
                      ),
                      RecipeSection(
                        title: 'タグ',
                        icon: Icons.sell_outlined,
                        titleStyle: RecipeTheme.readingHeading,
                        children: [
                          if (tags.isEmpty)
                            const Text(
                              'タグはまだありません',
                              style: RecipeTheme.readingNote,
                            )
                          else
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: tags
                                  .map((tag) => Chip(label: Text(tag)))
                                  .toList(growable: false),
                            ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => _editTags(context),
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('編集'),
                            ),
                          ),
                        ],
                      ),
                      CookingEntry(
                        key: ValueKey(
                          '${activeRecipe.id}:${activeRecipe.revision}',
                        ),
                        recipe: activeRecipe,
                        controller: controller,
                        cookingContext: cookingContext,
                        onReturned: () => setState(() => preparationVersion++),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            key: const Key('adjust_recipe'),
                            onPressed: () => openRecipeAdjustment(
                              context,
                              recipe: activeRecipe,
                              library: controller,
                            ),
                            icon: const Icon(Icons.auto_fix_high_outlined),
                            label: const Text('ChatGPTで調整'),
                          ),
                          OutlinedButton.icon(
                            key: const Key('open_feedback'),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => FeedbackScreen(
                                  recipeId: activeRecipe.id,
                                  controller: controller,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.rate_review_outlined),
                            label: const Text('調理後の評価'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _jumpToChange(
    String section,
    RecipeComparison comparison,
  ) async {
    if (section == '調理の工程') {
      setState(() => _showDetailedSteps = true);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
    if (!mounted) return;
    final target = _changeSections[section]?.currentContext;
    if (target != null) {
      if (!target.mounted) return;
      await Scrollable.ensureVisible(
        target,
        alignment: 0.05,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 250),
      );
    } else {
      if (!mounted) return;
      await showRecipeChangeDetails(
        context,
        comparison,
        comparison.changes
            .where((change) => change.section == section)
            .toList(),
        title: section,
      );
    }
  }

  Future<void> _editTags(BuildContext context) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _RecipeTagEditorDialog(
        recipeId: widget.recipe.id,
        controller: controller,
      ),
    );

    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('タグを保存しました。')));
    }
  }

  Future<void> _useDisplayedRecipe(RecipeDocument recipe) async {
    if (_activatingRevision) return;
    setState(() => _activatingRevision = true);
    final confirmed = await confirmFutureRecipe(context, recipe.revision);
    if (!mounted) return;
    if (!confirmed) {
      setState(() => _activatingRevision = false);
      return;
    }
    final result = await controller.setActiveRevision(
      recipe.id,
      recipe.revision,
    );
    if (!mounted) return;
    setState(() => _activatingRevision = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(result.message)));
  }
}

class _DetailQuantityRow extends StatelessWidget {
  const _DetailQuantityRow({
    required this.name,
    required this.quantity,
    required this.note,
    this.previousQuantity,
    this.compared = false,
  });
  final String name, quantity, note;
  final String? previousQuantity;
  final bool compared;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, bounds) {
            final stacked =
                bounds.maxWidth < 300 ||
                MediaQuery.textScalerOf(context).scale(17) > 24;
            final amount = RecipeComparedText(
              text: quantity,
              before: previousQuantity,
              compared: compared,
              textAlign: stacked ? TextAlign.start : TextAlign.end,
              style: RecipeTheme.readingBody.copyWith(
                fontWeight: FontWeight.w600,
                color: RecipeTheme.forest,
              ),
            );
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Text(name), const SizedBox(height: 4), amount],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: Text(name)),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: amount),
              ],
            );
          },
        ),
        if (note.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(note, style: RecipeTheme.readingNote),
        ],
      ],
    ),
  );
}

class _RecipeTagEditorDialog extends StatefulWidget {
  const _RecipeTagEditorDialog({
    required this.recipeId,
    required this.controller,
  });

  final String recipeId;
  final RecipeLibraryController controller;

  @override
  State<_RecipeTagEditorDialog> createState() => _RecipeTagEditorDialogState();
}

class _RecipeTagEditorDialogState extends State<_RecipeTagEditorDialog> {
  late final List<TextEditingController> _fields;
  String? _errorMessage;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final currentTags = widget.controller.tagsFor(widget.recipeId);
    _fields = List.generate(
      5,
      (index) => TextEditingController(
        text: index < currentTags.length ? currentTags[index] : '',
      ),
    );
  }

  @override
  void dispose() {
    for (final field in _fields) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('タグを編集'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('このレシピに5個まで設定できます。'),
            const SizedBox(height: 12),
            for (var index = 0; index < _fields.length; index++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  key: Key('recipe_tag_field_$index'),
                  controller: _fields[index],
                  maxLength: 30,
                  enabled: !_isSaving,
                  decoration: InputDecoration(labelText: 'タグ ${index + 1}'),
                ),
              ),
            if (_errorMessage != null)
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          key: const Key('save_recipe_tags_button'),
          onPressed: _isSaving ? null : _save,
          child: Text(_isSaving ? '保存中…' : '保存'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    final result = await widget.controller.setTags(
      widget.recipeId,
      _fields.map((field) => field.text),
    );
    if (!mounted) {
      return;
    }
    if (result.status == RecipeTagSaveStatus.saved) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _isSaving = false;
      _errorMessage = result.message;
    });
  }
}
