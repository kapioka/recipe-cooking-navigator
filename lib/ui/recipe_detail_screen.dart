import 'package:flutter/material.dart';

import '../application/recipe_library_controller.dart';
import '../domain/recipe_document.dart';
import 'cooking_entry.dart';
import 'feedback_screen.dart';
import 'recipe_version_history_screen.dart';

class RecipeDetailScreen extends StatefulWidget {
  const RecipeDetailScreen({
    required this.recipe,
    required this.controller,
    super.key,
  });

  final RecipeDocument recipe;
  final RecipeLibraryController controller;

  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends State<RecipeDetailScreen> {
  late int selectedServings = widget.recipe.servings;
  late String activeIdentity = '${widget.recipe.id}:${widget.recipe.revision}';
  Set<String> checkedPreparation = {};
  bool preparationLoading = true;
  bool preparationSaving = false;
  String? preparationError;

  RecipeLibraryController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _loadPreparation(widget.recipe);
  }

  Future<void> _loadPreparation(RecipeDocument recipe) async {
    final identity = '${recipe.id}:${recipe.revision}';
    try {
      final checked = await controller.preparationStore.checked(
        recipe.id,
        recipe.revision,
      );
      final validIds = (recipe.recipeData['preparation'] as List<dynamic>)
          .map((item) => (item as Map<String, dynamic>)['id'] as String)
          .toSet();
      if (!validIds.containsAll(checked)) {
        throw const FormatException('保存済みの事前準備がRecipeと一致しません。');
      }
      if (mounted && identity == activeIdentity) {
        setState(() {
          checkedPreparation = checked;
          preparationLoading = false;
          preparationError = null;
        });
      }
    } catch (_) {
      if (mounted && identity == activeIdentity) {
        setState(() {
          preparationLoading = false;
          preparationError = '事前準備を読み込めません。保存状態は変更していません。';
        });
      }
    }
  }

  Future<void> _setPreparation(
    RecipeDocument recipe,
    String taskId,
    bool checked,
  ) async {
    if (preparationSaving || preparationError != null) return;
    setState(() => preparationSaving = true);
    try {
      await controller.preparationStore.setChecked(
        recipe.id,
        recipe.revision,
        taskId,
        checked,
      );
      if (mounted && activeIdentity == '${recipe.id}:${recipe.revision}') {
        setState(() {
          checkedPreparation = {...checkedPreparation};
          if (checked) {
            checkedPreparation.add(taskId);
          } else {
            checkedPreparation.remove(taskId);
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => preparationError = '事前準備を保存できません。チェック状態は変更していません。');
      }
    } finally {
      if (mounted) setState(() => preparationSaving = false);
    }
  }

  Future<void> _resetPreparation(RecipeDocument recipe) async {
    if (preparationSaving || preparationError != null) return;
    setState(() => preparationSaving = true);
    try {
      await controller.preparationStore.reset(recipe.id, recipe.revision);
      if (mounted && activeIdentity == '${recipe.id}:${recipe.revision}') {
        setState(() => checkedPreparation = {});
      }
    } catch (_) {
      if (mounted) {
        setState(() => preparationError = '事前準備をリセットできません。保存状態は変更していません。');
      }
    } finally {
      if (mounted) setState(() => preparationSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final activeRecipe =
            controller.activeRecipeFor(widget.recipe.id) ?? widget.recipe;
        final identity = '${activeRecipe.id}:${activeRecipe.revision}';
        if (identity != activeIdentity) {
          activeIdentity = identity;
          selectedServings = activeRecipe.servings;
          checkedPreparation = {};
          preparationLoading = true;
          preparationError = null;
          _loadPreparation(activeRecipe);
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
        return Scaffold(
          appBar: AppBar(
            title: const Text('レシピ詳細'),
            actions: [
              IconButton(
                key: const Key('edit_recipe_tags_button'),
                tooltip: 'タグを編集',
                onPressed: () => _editTags(context),
                icon: const Icon(Icons.sell_outlined),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Text(
                activeRecipe.title,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    key: const Key('selected_servings_chip'),
                    label: Text('$selectedServings人分'),
                  ),
                  Chip(
                    label: Text(
                      '目安${activeRecipe.totalTimeMinutes}分（基準${activeRecipe.servings}人分）',
                    ),
                  ),
                  Chip(
                    label: Text('AI想定難易度 ${activeRecipe.estimatedDifficulty}'),
                  ),
                  Chip(
                    key: const Key('active_recipe_version_chip'),
                    label: Text('Active Version ${activeRecipe.revision}'),
                  ),
                  if (latestRecipe != null &&
                      latestRecipe.revision != activeRecipe.revision)
                    Chip(
                      label: Text('Latest Version ${latestRecipe.revision}'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Semantics(
                label: '調理人数、現在$selectedServings人分',
                child: Row(
                  children: [
                    IconButton.outlined(
                      key: const Key('decrease_servings'),
                      tooltip: '人数を1人減らす',
                      onPressed: selectedServings > activeRecipe.minServings
                          ? () => setState(() => selectedServings--)
                          : null,
                      icon: const Icon(Icons.remove),
                    ),
                    Expanded(
                      child: Text(
                        '基準 ${activeRecipe.servings}人分 → 選択 $selectedServings人分',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton.outlined(
                      key: const Key('increase_servings'),
                      tooltip: '人数を1人増やす',
                      onPressed: selectedServings < activeRecipe.maxServings
                          ? () => setState(() => selectedServings++)
                          : null,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('reset_servings'),
                  onPressed: selectedServings == activeRecipe.servings
                      ? null
                      : () => setState(
                          () => selectedServings = activeRecipe.servings,
                        ),
                  child: const Text('基準人数に戻す'),
                ),
              ),
              Text(
                activeRecipe.minServings == activeRecipe.maxServings
                    ? 'このレシピは人数変更できません。${activeRecipe.servingAdjustmentNote}'
                    : selectedServings == activeRecipe.servings
                    ? activeRecipe.servingAdjustmentNote
                    : '材料を$selectedServings人分に換算しています。加熱時間・火加減・器具は自動調整されません。\n${activeRecipe.servingAdjustmentNote}',
                key: const Key('serving_adjustment_note'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('open_version_history'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RecipeVersionHistoryScreen(
                      recipeId: activeRecipe.id,
                      controller: controller,
                    ),
                  ),
                ),
                icon: const Icon(Icons.history),
                label: Text('Version履歴（${revisions.length}件）'),
              ),
              const SizedBox(height: 24),
              CookingEntry(
                key: ValueKey('${activeRecipe.id}:${activeRecipe.revision}'),
                recipe: activeRecipe,
                controller: controller,
                cookingContext: cookingContext,
              ),
              const SizedBox(height: 12),
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
                label: const Text('調理後の評価・ChatGPTで改善'),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'タグ',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _editTags(context),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('編集'),
                  ),
                ],
              ),
              if (tags.isEmpty)
                const Text('タグはまだありません')
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: tags
                      .map((tag) => Chip(label: Text(tag)))
                      .toList(growable: false),
                ),
              const SizedBox(height: 24),
              Text('材料', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              ...ingredientSummaries.map(
                (ingredient) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(ingredient.name),
                  trailing: Text(ingredient.quantity),
                  subtitle:
                      [
                        ingredient.details,
                        ingredient.note,
                      ].whereType<String>().isEmpty
                      ? null
                      : Text(
                          [
                            ingredient.details,
                            ingredient.note,
                          ].whereType<String>().join('\n'),
                        ),
                ),
              ),
              if (utensils.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('器具', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                for (final utensil in utensils)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(utensil['name'] as String),
                    trailing: Text('${utensil['quantity']}'),
                    subtitle: utensil['reuse_note'] == null
                        ? null
                        : Text(
                            activeRecipe
                                .renderText(
                                  utensil['reuse_note'] as List<dynamic>,
                                  cookingContext,
                                )
                                .displayText,
                          ),
                  ),
              ],
              if (preparation.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('事前準備', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                if (preparationLoading) const LinearProgressIndicator(),
                if (preparationError != null) ...[
                  Text(
                    preparationError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        preparationLoading = true;
                        preparationError = null;
                      });
                      _loadPreparation(activeRecipe);
                    },
                    child: const Text('再読み込み'),
                  ),
                ],
                for (final entry in preparation.indexed)
                  CheckboxListTile(
                    key: Key('preparation_${entry.$2['id']}'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: checkedPreparation.contains(entry.$2['id']),
                    onChanged:
                        preparationLoading ||
                            preparationSaving ||
                            preparationError != null
                        ? null
                        : (value) => _setPreparation(
                            activeRecipe,
                            entry.$2['id'] as String,
                            value ?? false,
                          ),
                    title: Text(
                      activeRecipe
                          .renderText(
                            entry.$2['text'] as List<dynamic>,
                            cookingContext,
                          )
                          .displayText,
                    ),
                  ),
                if (checkedPreparation.isNotEmpty)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      key: const Key('reset_preparation'),
                      onPressed: preparationSaving || preparationError != null
                          ? null
                          : () => _resetPreparation(activeRecipe),
                      child: const Text('チェックをリセット'),
                    ),
                  ),
                const Text('チェックはこのVersionに保存されます。次回の調理前に再確認してください。'),
              ],
              const SizedBox(height: 20),
              Text('全体工程', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              ...activeRecipe.overview.indexed.map(
                (entry) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(radius: 13, child: Text('${entry.$1 + 1}')),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          activeRecipe
                              .renderText(entry.$2, cookingContext)
                              .displayText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
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
                  decoration: InputDecoration(
                    labelText: 'タグ ${index + 1}',
                    border: const OutlineInputBorder(),
                  ),
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
