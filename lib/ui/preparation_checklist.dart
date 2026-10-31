import 'package:flutter/material.dart';

import '../data/preparation_checklist_store.dart';
import '../domain/cooking_context.dart';
import '../domain/recipe_document.dart';

/// The same version-specific checklist is used before and during cooking.
class PreparationChecklist extends StatefulWidget {
  const PreparationChecklist({
    required this.recipe,
    required this.cookingContext,
    required this.store,
    this.showHeading = true,
    this.onBusy,
    super.key,
  });

  final RecipeDocument recipe;
  final CookingContext cookingContext;
  final PreparationChecklistStore store;
  final bool showHeading;
  final ValueChanged<bool>? onBusy;

  @override
  State<PreparationChecklist> createState() => _PreparationChecklistState();
}

class _PreparationChecklistState extends State<PreparationChecklist> {
  Set<String> checkedPreparation = {};
  bool preparationLoading = true;
  bool preparationSaving = false;
  String? preparationError;
  String get activeIdentity => '${widget.recipe.id}:${widget.recipe.revision}';

  @override
  void initState() {
    super.initState();
    _loadPreparation(widget.recipe);
  }

  Future<void> _loadPreparation(RecipeDocument recipe) async {
    final identity = '${recipe.id}:${recipe.revision}';
    try {
      final checked = await widget.store.checked(recipe.id, recipe.revision);
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
    widget.onBusy?.call(true);
    try {
      await widget.store.setChecked(
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
      if (mounted) {
        setState(() => preparationSaving = false);
        widget.onBusy?.call(false);
      }
    }
  }

  Future<void> _resetPreparation(RecipeDocument recipe) async {
    if (preparationSaving || preparationError != null) return;
    setState(() => preparationSaving = true);
    widget.onBusy?.call(true);
    try {
      await widget.store.reset(recipe.id, recipe.revision);
      if (mounted && activeIdentity == '${recipe.id}:${recipe.revision}') {
        setState(() => checkedPreparation = {});
      }
    } catch (_) {
      if (mounted) {
        setState(() => preparationError = '事前準備をリセットできません。保存状態は変更していません。');
      }
    } finally {
      if (mounted) {
        setState(() => preparationSaving = false);
        widget.onBusy?.call(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final preparation = widget.recipe.recipeData['preparation'] as List;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (preparation.isNotEmpty) ...[
          if (widget.showHeading) ...[
            const SizedBox(height: 20),
            Text('事前準備', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
          ],
          if (preparationLoading) const LinearProgressIndicator(),
          if (preparationError != null) ...[
            Text(
              preparationError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  preparationLoading = true;
                  preparationError = null;
                });
                _loadPreparation(widget.recipe);
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
                      widget.recipe,
                      entry.$2['id'] as String,
                      value ?? false,
                    ),
              title: Text(
                widget.recipe
                    .renderText(
                      entry.$2['text'] as List<dynamic>,
                      widget.cookingContext,
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
                    : () => _resetPreparation(widget.recipe),
                child: const Text('チェックをリセット'),
              ),
            ),
          const Text('チェックはこのVersionに保存されます。次回の調理前に再確認してください。'),
        ],
        if (preparation.isEmpty) const Text('このレシピに下準備の指定はありません。'),
      ],
    );
  }
}
