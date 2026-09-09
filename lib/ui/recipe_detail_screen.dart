import 'package:flutter/material.dart';

import '../application/recipe_library_controller.dart';
import '../domain/recipe_document.dart';
import 'cooking_entry.dart';
import 'recipe_version_history_screen.dart';

class RecipeDetailScreen extends StatelessWidget {
  const RecipeDetailScreen({
    required this.recipe,
    required this.controller,
    super.key,
  });

  final RecipeDocument recipe;
  final RecipeLibraryController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final activeRecipe = controller.activeRecipeFor(recipe.id) ?? recipe;
        final latestRecipe = controller.latestRecipeFor(recipe.id);
        final revisions = controller.revisionsFor(recipe.id);
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
                  Chip(label: Text('${activeRecipe.servings}人分')),
                  Chip(label: Text('${activeRecipe.totalTimeMinutes}分')),
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
              ...activeRecipe.ingredients.map(
                (ingredient) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(ingredient.name),
                  trailing: Text(ingredient.quantity),
                  subtitle: ingredient.note == null
                      ? null
                      : Text(ingredient.note!),
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
                        : Text(utensil['reuse_note'] as String),
                  ),
              ],
              if (preparation.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('事前準備', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                for (final entry in preparation.indexed)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 13,
                      child: Text('${entry.$1 + 1}'),
                    ),
                    title: Text(entry.$2['text'] as String),
                  ),
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
                      Expanded(child: Text(entry.$2)),
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
      builder: (_) =>
          _RecipeTagEditorDialog(recipeId: recipe.id, controller: controller),
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
