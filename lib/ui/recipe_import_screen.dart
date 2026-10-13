import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/recipe_library_controller.dart';
import 'recipe_detail_screen.dart';
import 'recipe_preview_content.dart';

Future<String?> showRecipePasteDialog(BuildContext context) =>
    showDialog<String>(context: context, builder: (_) => const _PasteDialog());

class _PasteDialog extends StatefulWidget {
  const _PasteDialog();
  @override
  State<_PasteDialog> createState() => _PasteDialogState();
}

class _PasteDialogState extends State<_PasteDialog> {
  final _text = TextEditingController();
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('コピーしたレシピを貼り付け'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('paste_recipe_source'),
            controller: _text,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(hintText: 'ChatGPTから届いたレシピ全体'),
          ),
          TextButton(
            onPressed: () async {
              final data = await Clipboard.getData(Clipboard.kTextPlain);
              if (mounted && data?.text != null) _text.text = data!.text!;
            },
            child: const Text('クリップボードから貼り付け'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('キャンセル'),
      ),
      FilledButton(
        key: const Key('preview_pasted_recipe'),
        onPressed: () => Navigator.pop(context, _text.text),
        child: const Text('内容を確認'),
      ),
    ],
  );
}

class RecipeImportScreen extends StatefulWidget {
  const RecipeImportScreen({
    required this.library,
    required this.preview,
    super.key,
  });
  final RecipeLibraryController library;
  final RecipeImportPreview preview;
  @override
  State<RecipeImportScreen> createState() => _RecipeImportScreenState();
}

class _RecipeImportScreenState extends State<RecipeImportScreen> {
  late RecipeImportPreview _preview = widget.preview;
  bool _saving = false, _allowPop = false;
  String? _error;
  @override
  void dispose() {
    final library = widget.library;
    final preview = _preview;
    scheduleMicrotask(() => library.cancelPreparedImport(preview));
    super.dispose();
  }

  Future<void> _leave() async {
    if (_saving) return;
    final discard =
        widget.library.isStoredPreview(_preview) ||
        await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('保存せずに戻りますか？'),
                content: const Text('このレシピはまだ保存されていません。'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('内容確認を続ける'),
                  ),
                  TextButton(
                    key: const Key('discard_recipe_import'),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('保存せず戻る'),
                  ),
                ],
              ),
            ) ==
            true;
    if (!discard || !mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final prepared = await widget.library.reprepareImport(_preview);
    RecipeImportResult result;
    if (prepared.preview == null) {
      result = RecipeImportResult(RecipeImportStatus.failed, prepared.message);
    } else {
      _preview = prepared.preview!;
      result = await widget.library.confirmPreparedImport(
        _preview,
        preserveActive: true,
      );
    }
    if (!mounted) return;
    if (result.status == RecipeImportStatus.failed) {
      setState(() {
        _saving = false;
        _error = '保存できませんでした。内容は残っています。\n${result.message}';
      });
      return;
    }
    final recipe = widget.library.revisionFor(
      _preview.recipeId,
      _preview.revision,
    );
    if (recipe == null) {
      setState(() {
        _saving = false;
        _error = '保存状態を確認できませんでした。';
      });
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.status == RecipeImportStatus.alreadyExists
              ? '保存済みのレシピを開きました'
              : recipe.parentRevision == null
              ? '保存しました'
              : '新しいバージョンを保存しました。使用中のバージョンは変わっていません',
        ),
      ),
    );
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => RecipeDetailScreen(
          recipe: recipe,
          controller: widget.library,
          showExactRevision: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      appBar: AppBar(title: const Text('レシピの内容確認')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    RecipePreviewContent(
                      preview: _preview,
                      saved: widget.library.isStoredPreview(_preview),
                      titleKey: const Key('recipe_import_preview_title'),
                    ),
                    if (_error != null)
                      Semantics(liveRegion: true, child: Text(_error!)),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    key: const Key('confirm_recipe_import'),
                    onPressed: _saving ? null : _save,
                    child: Text(
                      _saving
                          ? '保存しています'
                          : _error == null
                          ? widget.library.isStoredPreview(_preview)
                                ? '保存済みのレシピを開く'
                                : 'このレシピを保存'
                          : '保存を再試行',
                    ),
                  ),
                  TextButton(
                    key: const Key('cancel_recipe_import'),
                    onPressed: _saving ? null : _leave,
                    child: const Text('キャンセル'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
