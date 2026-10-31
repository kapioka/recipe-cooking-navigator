import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/recipe_library_controller.dart';
import '../domain/ai_recipe_request.dart';
import '../domain/recipe_document.dart';
import '../platform/ai_request_platform.dart';
import 'ai_recipe_request_screen.dart';

Future<void> openRecipeAdjustment(
  BuildContext context, {
  required RecipeDocument recipe,
  required RecipeLibraryController library,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => AiRecipeRequestScreen(
      library: library,
      initialRequest: AiRecipeRequest.recreate(
        recipe: recipe,
        nextRevision:
            (library.latestRecipeFor(recipe.id)?.revision ?? recipe.revision) +
            1,
      ),
    ),
  ),
);

/// Export only the displayed recipe, without saving an assessment or session.
class RecipeShareMenu extends StatefulWidget {
  const RecipeShareMenu({
    required this.recipe,
    this.onAdjust,
    this.platform = const AndroidAiRequestPlatform(),
    super.key,
  });
  final RecipeDocument recipe;
  final VoidCallback? onAdjust;
  final AiRequestPlatform platform;

  @override
  State<RecipeShareMenu> createState() => _RecipeShareMenuState();
}

class _RecipeShareMenuState extends State<RecipeShareMenu> {
  bool _busy = false;

  Future<void> _select(String action) async {
    if (_busy) return;
    if (action == 'adjust') {
      widget.onAdjust?.call();
      return;
    }
    final recipe = widget.recipe;
    final source = jsonEncode(recipe.raw);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      if (action == 'copy') {
        await Clipboard.setData(ClipboardData(text: source));
      } else {
        await widget.platform.share(source);
      }
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            action == 'copy'
                ? 'バージョン ${recipe.revision}のレシピをコピーしました。'
                : '共有先を選んでください。',
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('コピー・共有を開始できませんでした。もう一度お試しください。')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    enabled: !_busy,
    tooltip: 'レシピの操作',
    onSelected: _select,
    itemBuilder: (_) => [
      if (widget.onAdjust != null)
        const PopupMenuItem(value: 'adjust', child: Text('ChatGPTで調整')),
      const PopupMenuItem(value: 'copy', child: Text('レシピをコピー')),
      const PopupMenuItem(value: 'share', child: Text('レシピを共有')),
    ],
  );
}
