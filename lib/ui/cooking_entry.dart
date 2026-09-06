import 'package:flutter/material.dart';

import '../application/recipe_library_controller.dart';
import '../domain/recipe_document.dart';
import 'cooking_screen.dart';

class CookingEntry extends StatefulWidget {
  const CookingEntry({
    required this.recipe,
    required this.controller,
    super.key,
  });
  final RecipeDocument recipe;
  final RecipeLibraryController controller;
  @override
  State<CookingEntry> createState() => _CookingEntryState();
}

class _CookingEntryState extends State<CookingEntry> {
  Map<String, dynamic>? progress;
  RecipeDocument? savedRecipe;
  int? savedIndex;
  String? error;
  bool loading = true;
  bool busy = false;
  bool unreadable = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await widget.controller.cookingStore.read();
      final p =
          (data['progress'] as Map)[widget.recipe.id] as Map<String, dynamic>?;
      final recipe = p == null
          ? null
          : widget.controller.revisionFor(
              widget.recipe.id,
              p['revision'] as int,
            );
      final index = recipe?.steps.indexWhere((s) => s['id'] == p!['step_id']);
      if (mounted) {
        setState(() {
          progress = p;
          savedRecipe = recipe;
          savedIndex = index;
          error = p != null && (recipe == null || index == null || index < 0)
              ? '保存したVersionまたは工程が見つかりません。「最初から」で開始方法を選べます。'
              : null;
          unreadable = false;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          error = '調理位置を読み込めません。保存データは変更していません。';
          unreadable = true;
          loading = false;
        });
      }
    }
  }

  Future<void> _start(bool resume) async {
    if (busy) return;
    if (!resume && progress != null) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('最初から始めますか？'),
          content: Text(
            'Version ${widget.recipe.revision}の先頭から開始します。現在の途中位置を更新します。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('最初から'),
            ),
          ],
        ),
      );
      if (yes != true || !mounted) {
        return;
      }
    }
    final recipe = resume ? savedRecipe! : widget.recipe;
    final index = resume ? savedIndex! : 0;
    setState(() => busy = true);
    try {
      await widget.controller.cookingStore.savePosition(
        recipe.id,
        recipe.revision,
        recipe.steps[index]['id'] as String,
        restart: !resume,
      );
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CookingScreen(
            recipe: recipe,
            store: widget.controller.cookingStore,
            initialIndex: index,
          ),
        ),
      );
      await _load();
    } catch (_) {
      if (mounted) {
        setState(() => error = '調理位置を保存できませんでした。開始していません。');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (loading) const LinearProgressIndicator(),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (progress != null &&
              savedRecipe != null &&
              savedIndex != null &&
              savedIndex! >= 0) ...[
            Text('調理途中です・Version ${savedRecipe!.revision}'),
            Text(
              '工程 ${savedIndex! + 1} / ${savedRecipe!.steps.length} ${savedRecipe!.steps[savedIndex!]['title']}',
            ),
            FilledButton(
              key: const Key('resume_cooking'),
              onPressed: busy ? null : () => _start(true),
              child: const Text('続きから'),
            ),
          ],
          if (unreadable)
            TextButton(onPressed: _load, child: const Text('再読み込み'))
          else
            FilledButton(
              key: const Key('start_cooking'),
              onPressed: loading || busy ? null : () => _start(false),
              child: Text(progress == null ? '調理開始' : '最初から'),
            ),
        ],
      ),
    ),
  );
}
