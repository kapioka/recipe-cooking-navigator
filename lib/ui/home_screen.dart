import 'package:flutter/material.dart';

import '../application/recipe_library_controller.dart';
import '../domain/recipe_document.dart';
import 'about_dialog.dart';
import 'ai_recipe_request_screen.dart';
import 'recipe_detail_screen.dart';
import 'kitchen_screen.dart';
import 'kitchen_scope.dart';
import 'preference_scope.dart';
import 'preference_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.controller, this.onOpenKitchen, super.key});

  final RecipeLibraryController controller;
  final VoidCallback? onOpenKitchen;

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  late final TextEditingController _searchController;

  RecipeLibraryController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: controller.searchQuery);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('レシピ'),
        actions: [
          if (PreferenceControllerScope.maybeOf(context)
              case final preferences?)
            IconButton(
              key: const Key('open_preferences'),
              tooltip: '料理の好み',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PreferenceScreen(
                    controller: preferences,
                    recipes: controller.recipes,
                  ),
                ),
              ),
              icon: const Icon(Icons.tune),
            ),
          IconButton(
            key: const Key('app_information_button'),
            tooltip: 'このアプリについて',
            onPressed: () => showAppInformationDialog(context),
            icon: const Icon(Icons.info_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!KitchenScope.contains(context)) ...[
                        FilledButton.tonalIcon(
                          key: const Key('open_kitchen'),
                          onPressed:
                              widget.onOpenKitchen ??
                              () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      KitchenScreen(library: controller),
                                ),
                              ),
                          icon: const Icon(Icons.kitchen_outlined),
                          label: const Text('キッチンツールを開く'),
                        ),
                        const SizedBox(height: 4),
                      ],
                      OutlinedButton.icon(
                        key: const Key('open_recipe_archive'),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                _ArchiveScreen(controller: controller),
                          ),
                        ),
                        icon: const Icon(Icons.archive_outlined),
                        label: const Text('アーカイブ'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: TextField(
                    key: const Key('recipe_search_field'),
                    controller: _searchController,
                    onChanged: controller.setSearchQuery,
                    decoration: InputDecoration(
                      hintText: '料理名・食材・タグで検索',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: controller.searchQuery.isEmpty
                          ? null
                          : IconButton(
                              key: const Key('clear_recipe_search'),
                              tooltip: '検索をクリア',
                              onPressed: _clearSearch,
                              icon: const Icon(Icons.clear),
                            ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                if (controller.searchSuggestions.isNotEmpty)
                  _SuggestionList(
                    suggestions: controller.searchSuggestions,
                    onSelected: _selectSuggestion,
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton.icon(
                        key: const Key('check_recipe_inbox_button'),
                        onPressed: controller.isBusy ? null : _checkInbox,
                        icon: controller.isCheckingInbox
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.cloud_download_outlined),
                        label: Text(
                          controller.isCheckingInbox ? '確認中…' : '新しいレシピを確認',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              key: const Key('create_chatgpt_recipe'),
                              onPressed: controller.isBusy
                                  ? null
                                  : () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => AiRecipeRequestScreen(
                                          library: controller,
                                        ),
                                      ),
                                    ),
                              child: const Text('ChatGPTでレシピを作る'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              key: const Key('paste_recipe'),
                              onPressed: controller.isBusy
                                  ? null
                                  : _pasteRecipe,
                              child: const Text('レシピを貼り付け'),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              key: const Key('import_recipe_button'),
                              onPressed: controller.isImporting
                                  ? null
                                  : () => _importRecipe(context),
                              icon: controller.isImporting
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.file_open_outlined),
                              label: Text(
                                controller.isImporting
                                    ? '読み込み中…'
                                    : 'ChatGPTレシピを取り込む',
                              ),
                            ),
                          ),
                          IconButton(
                            key: const Key('select_inbox_folder_button'),
                            tooltip: 'Google Drive / AI / Recipe Cooking Navigator / Inboxを選ぶ',
                            onPressed: controller.isInboxBusy
                                ? null
                                : _selectInboxFolder,
                            icon: const Icon(
                              Icons.drive_folder_upload_outlined,
                            ),
                          ),
                        ],
                      ),
                      if (controller.inboxFolder case final folder?) ...[
                        const SizedBox(height: 4),
                        Text(
                          '接続先: Google Drive / ${folder.displayName}',
                          key: const Key('recipe_inbox_connection'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                if (controller.loadError case final error?)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(error),
                      ),
                    ),
                  ),
                if (controller.legacyDataPresent)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          '旧形式のレシピは表示していません。新しい指示文で再作成してください。旧データは削除していません。',
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: controller.totalRecipeCount == 0
                      ? const _EmptyLibrary()
                      : controller.recipes.isEmpty
                      ? _NoSearchResults(query: controller.searchQuery)
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: controller.recipes.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            return _RecipeCard(
                              recipe: controller.recipes[index],
                              tags: controller.tagsFor(
                                controller.recipes[index].id,
                              ),
                              controller: controller,
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _clearSearch() {
    _searchController.clear();
    controller.setSearchQuery('');
  }

  void _selectSuggestion(RecipeSearchSuggestion suggestion) {
    _searchController.text = suggestion.label;
    _searchController.selection = TextSelection.collapsed(
      offset: suggestion.label.length,
    );
    controller.setSearchQuery(suggestion.label);
    FocusScope.of(context).unfocus();
  }

  Future<void> _importRecipe(BuildContext context) async {
    final preparation = await controller.prepareImportFromFile();
    if (!context.mounted) {
      final preview = preparation.preview;
      if (preview != null) controller.cancelPreparedImport(preview);
      return;
    }
    await _showPreparedImport(context, preparation);
  }

  Future<void> _pasteRecipe() async {
    final source = await showDialog<String>(
      context: context,
      builder: (_) => const _PasteRecipeDialog(),
    );
    if (source == null || !mounted) return;
    await importSharedSource(source);
  }

  Future<void> importSharedSource(String source) async {
    final preparation = await controller.prepareImportSource(source);
    if (!mounted) {
      final preview = preparation.preview;
      if (preview != null) controller.cancelPreparedImport(preview);
      return;
    }
    await _showPreparedImport(context, preparation);
  }

  void showSharedImportError(String message) {
    if (mounted) {
      _showImportResult(
        context,
        RecipeImportResult(RecipeImportStatus.failed, message),
      );
    }
  }

  Future<void> _showPreparedImport(
    BuildContext context,
    RecipeImportPreparation preparation,
  ) async {
    if (!context.mounted) {
      final preview = preparation.preview;
      if (preview != null) controller.cancelPreparedImport(preview);
      return;
    }
    if (preparation.status == RecipeImportPreparationStatus.cancelled) return;
    if (preparation.status == RecipeImportPreparationStatus.failed) {
      _showImportResult(
        context,
        RecipeImportResult(RecipeImportStatus.failed, preparation.message),
      );
      return;
    }

    final preview = preparation.preview!;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('このレシピを取り込みますか？'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                preview.title,
                key: const Key('recipe_import_preview_title'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text('Version ${preview.revision}'),
              if (preview.parentRevision case final parent?)
                Text('Version $parentから派生'),
              Text('${preview.servings}人分・約${preview.totalTimeMinutes}分'),
              Text('材料 ${preview.ingredientCount}件・工程 ${preview.stepCount}件'),
              const SizedBox(height: 12),
              Text(
                'レシピID: ${preview.recipeId}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              const Text('取り込むとこのVersionを端末に保存します。既存のVersionは上書きしません。'),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const Key('cancel_recipe_import'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            key: const Key('confirm_recipe_import'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('取り込む'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      controller.cancelPreparedImport(preview);
      return;
    }

    final result = await controller.confirmPreparedImport(preview);
    if (!context.mounted) return;
    _showImportResult(context, result);
  }

  void _showImportResult(BuildContext context, RecipeImportResult result) {
    final colorScheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.status == RecipeImportStatus.failed
            ? colorScheme.error
            : null,
      ),
    );
  }

  Future<void> _selectInboxFolder() async {
    final result = await controller.selectInboxFolder();
    if (!mounted ||
        result.status == RecipeInboxFolderSelectionStatus.cancelled) {
      return;
    }
    final colorScheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor:
            result.status == RecipeInboxFolderSelectionStatus.failed
            ? colorScheme.error
            : null,
      ),
    );
  }

  Future<void> _checkInbox() async {
    var result = await controller.checkInbox();
    if (!mounted) {
      return;
    }

    if (result.status == RecipeInboxRunStatus.folderSelectionRequired) {
      final selectFolder = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Inboxフォルダを選択'),
          content: Text(
            '${result.message}\n\nGoogle Drive / AI / Recipe Cooking Navigator / Inboxを選択してください。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              key: const Key('confirm_select_inbox_folder'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('フォルダを選ぶ'),
            ),
          ],
        ),
      );
      if (selectFolder != true || !mounted) {
        return;
      }

      final selection = await controller.selectInboxFolder();
      if (!mounted ||
          selection.status == RecipeInboxFolderSelectionStatus.cancelled) {
        return;
      }
      if (selection.status == RecipeInboxFolderSelectionStatus.failed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(selection.message),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return;
      }
      result = await controller.checkInbox();
      if (!mounted) {
        return;
      }
    }

    if (result.status == RecipeInboxRunStatus.completed) {
      await _showInboxResult(result);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  Future<void> _showInboxResult(RecipeInboxRunResult result) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Inboxの確認結果'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(result.message),
              const SizedBox(height: 4),
              const Text('Inbox内のファイルは変更していません。'),
              if (result.files.isNotEmpty) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: (result.files.length * 72).clamp(72, 240).toDouble(),
                  child: ListView.separated(
                    itemCount: result.files.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final file = result.files[index];
                      final (icon, color) = switch (file.status) {
                        RecipeInboxFileStatus.imported => (
                          Icons.check_circle_outline,
                          Theme.of(context).colorScheme.primary,
                        ),
                        RecipeInboxFileStatus.skipped => (
                          Icons.skip_next_outlined,
                          Theme.of(context).colorScheme.secondary,
                        ),
                        RecipeInboxFileStatus.rejected => (
                          Icons.error_outline,
                          Theme.of(context).colorScheme.error,
                        ),
                      };
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(icon, color: color),
                        title: Text(file.fileName),
                        subtitle: Text(file.message),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }
}

class _SuggestionList extends StatelessWidget {
  const _SuggestionList({required this.suggestions, required this.onSelected});

  final List<RecipeSearchSuggestion> suggestions;
  final ValueChanged<RecipeSearchSuggestion> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        margin: EdgeInsets.zero,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: suggestions.length,
            itemBuilder: (context, index) {
              final suggestion = suggestions[index];
              return ListTile(
                dense: true,
                leading: Icon(_suggestionIcon(suggestion.kind)),
                title: Text(suggestion.label),
                trailing: Text(_suggestionKindLabel(suggestion.kind)),
                onTap: () => onSelected(suggestion),
              );
            },
          ),
        ),
      ),
    );
  }

  IconData _suggestionIcon(RecipeSearchSuggestionKind kind) {
    return switch (kind) {
      RecipeSearchSuggestionKind.recipeTitle => Icons.menu_book_outlined,
      RecipeSearchSuggestionKind.ingredient => Icons.restaurant_outlined,
      RecipeSearchSuggestionKind.tag => Icons.sell_outlined,
    };
  }

  String _suggestionKindLabel(RecipeSearchSuggestionKind kind) {
    return switch (kind) {
      RecipeSearchSuggestionKind.recipeTitle => '料理名',
      RecipeSearchSuggestionKind.ingredient => '食材',
      RecipeSearchSuggestionKind.tag => 'タグ',
    };
  }
}

class _PasteRecipeDialog extends StatefulWidget {
  const _PasteRecipeDialog();
  @override
  State<_PasteRecipeDialog> createState() => _PasteRecipeDialogState();
}

class _PasteRecipeDialogState extends State<_PasteRecipeDialog> {
  final _input = TextEditingController();
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('ChatGPTのレシピを貼り付け'),
    content: SizedBox(
      width: 520,
      child: TextField(
        key: const Key('paste_recipe_source'),
        controller: _input,
        minLines: 5,
        maxLines: 10,
        decoration: const InputDecoration(
          hintText: '回答のRecipe JSON全体を貼り付けてください',
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('キャンセル'),
      ),
      FilledButton(
        key: const Key('preview_pasted_recipe'),
        onPressed: () => Navigator.pop(context, _input.text),
        child: const Text('内容を確認'),
      ),
    ],
  );
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.menu_book_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('まだレシピがありません', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'ChatGPTで作ったレシピファイルを取り込むと、ここに表示されます。',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _NoSearchResults extends StatelessWidget {
  const _NoSearchResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text('「$query」に一致するレシピはありません'),
          ],
        ),
      ),
    );
  }
}

class _RecipeCard extends StatelessWidget {
  const _RecipeCard({
    required this.recipe,
    required this.tags,
    required this.controller,
  });

  final RecipeDocument recipe;
  final List<String> tags;
  final RecipeLibraryController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(
          recipe.title,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${recipe.servings}人分 ・ ${recipe.totalTimeMinutes}分 ・ '
                '難易度${recipe.estimatedDifficulty} ・ Active Version ${recipe.revision}',
              ),
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: tags
                      .map(
                        (tag) => Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(tag),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
            ],
          ),
        ),
        trailing: PopupMenuButton<String>(
          tooltip: 'レシピの操作',
          onSelected: (value) async {
            if (value != 'archive') return;
            final result = await controller.setArchived(recipe.id, true);
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(result)));
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'archive', child: Text('アーカイブへ移す')),
          ],
        ),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  RecipeDetailScreen(recipe: recipe, controller: controller),
            ),
          );
        },
      ),
    );
  }
}

class _ArchiveScreen extends StatelessWidget {
  const _ArchiveScreen({required this.controller});

  final RecipeLibraryController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('アーカイブ')),
    body: AnimatedBuilder(
      animation: controller,
      builder: (context, _) => controller.archivedRecipes.isEmpty
          ? const Center(child: Text('アーカイブしたレシピはありません'))
          : ListView.builder(
              itemCount: controller.archivedRecipes.length,
              itemBuilder: (context, index) {
                final recipe = controller.archivedRecipes[index];
                return ListTile(
                  key: Key('archived_recipe_${recipe.id}'),
                  title: Text(recipe.title),
                  subtitle: Text('Active Version ${recipe.revision}'),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'アーカイブの操作',
                    onSelected: (value) async {
                      if (value == 'restore') {
                        final result = await controller.setArchived(
                          recipe.id,
                          false,
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text(result)));
                        }
                        return;
                      }
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: const Text('レシピを完全削除しますか？'),
                          content: Text(
                            '「${recipe.title}」の全Version、タグ、事前準備、調理履歴と評価を端末から削除します。元に戻せません。\n\nGoogle DriveのInboxに元ファイルが残っている場合、次の確認で再取込されます。先にDrive側の元ファイルを取り除いてください。',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, false),
                              child: const Text('キャンセル'),
                            ),
                            FilledButton(
                              key: const Key('confirm_delete_archived_recipe'),
                              onPressed: () =>
                                  Navigator.pop(dialogContext, true),
                              child: const Text('完全削除'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed != true) return;
                      final result = await controller.deleteArchivedRecipe(
                        recipe.id,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(result)));
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'restore', child: Text('一覧へ戻す')),
                      PopupMenuItem(value: 'delete', child: Text('完全削除')),
                    ],
                  ),
                );
              },
            ),
    ),
  );
}
