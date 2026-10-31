import '../platform/ai_request_platform.dart';
import '../domain/recipe_validator.dart';
import 'recipe_section.dart';

import 'package:flutter/material.dart';

import '../application/recipe_library_controller.dart';
import '../domain/recipe_document.dart';
import 'about_dialog.dart';
import 'recipe_ai_scope.dart';
import 'recipe_ai_settings_screen.dart';
import 'recipe_import_screen.dart';
import 'ai_recipe_request_screen.dart';
import 'recipe_detail_screen.dart';
import 'kitchen_screen.dart';
import 'kitchen_scope.dart';
import 'preference_scope.dart';
import 'preference_screen.dart';
import 'recipe_photo_avatar.dart';
import 'recipe_theme.dart';
import 'recipe_difficulty_meter.dart';
import 'feedback_screen.dart';

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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('レシピ'),
      actions: [
        TextButton.icon(
          key: const Key('open_settings'),
          onPressed: _settings,
          icon: const Icon(Icons.settings_outlined),
          label: const Text('設定'),
        ),
      ],
    ),
    body: SafeArea(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
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
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (!KitchenScope.contains(context))
                                OutlinedButton.icon(
                                  key: const Key('open_kitchen'),
                                  onPressed:
                                      widget.onOpenKitchen ??
                                      () => Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) => KitchenScreen(
                                            library: controller,
                                          ),
                                        ),
                                      ),
                                  icon: const Icon(Icons.kitchen_outlined),
                                  label: const Text('キッチンツールを開く'),
                                ),
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
                          if (controller.searchSuggestions.isNotEmpty)
                            _SuggestionList(
                              suggestions: controller.searchSuggestions,
                              onSelected: _selectSuggestion,
                            ),
                          if (controller.loadError case final error?)
                            Text(error),
                          if (controller.legacyDataPresent)
                            ExpansionTile(
                              title: const Text('旧形式のデータがあります'),
                              children: const [
                                Text(
                                  '旧形式のレシピは表示していません。旧データは削除していません。新しい指示文で再作成できます。',
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (controller.totalRecipeCount == 0)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyLibrary(),
                    )
                  else if (controller.recipes.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _NoSearchResults(query: controller.searchQuery),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      sliver: SliverList.builder(
                        itemCount: controller.recipes.length,
                        itemBuilder: (context, index) => _RecipeCard(
                          recipe: controller.recipes[index],
                          tags: controller.tagsFor(
                            controller.recipes[index].id,
                          ),
                          controller: controller,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    key: const Key('create_chatgpt_recipe'),
                    onPressed: controller.isImporting
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  AiRecipeRequestScreen(library: controller),
                            ),
                          ),
                    icon: const Icon(Icons.add),
                    label: const Text('レシピを作る'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('open_recipe_import'),
                    onPressed: _importOptions,
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('レシピを取り込む'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _importOptions() async {
    final method = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(title: Text('レシピを取り込む')),
                ListTile(
                  key: const Key('paste_recipe'),
                  enabled: !controller.isImporting,
                  leading: const Icon(Icons.content_paste),
                  title: const Text('コピーしたレシピを貼り付け'),
                  subtitle: const Text('ChatGPTから届いた回答を確認して保存'),
                  onTap: () => Navigator.pop(context, 'paste'),
                ),
                ListTile(
                  key: const Key('import_recipe_button'),
                  enabled: !controller.isImporting,
                  leading: const Icon(Icons.file_open_outlined),
                  title: const Text('ファイルから選ぶ'),
                  subtitle: const Text('端末やDriveから1つ選び、内容を確認'),
                  onTap: () => Navigator.pop(context, 'file'),
                ),
                ListTile(
                  key: const Key('check_recipe_inbox_button'),
                  enabled: !controller.isBusy,
                  leading: const Icon(Icons.cloud_download_outlined),
                  title: Text(
                    controller.isCheckingInbox
                        ? '受け取りフォルダを確認中…'
                        : '受け取りフォルダを確認',
                  ),
                  subtitle: const Text('この操作でフォルダ内を検証し、まとめて保存します'),
                  onTap: () => Navigator.pop(context, 'inbox'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted) return;
    switch (method) {
      case 'paste':
        await _pasteRecipe();
      case 'file':
        await _importRecipe(context);
      case 'inbox':
        await _checkInbox();
    }
  }

  Future<void> _settings() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('設定')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            RecipeSection(
              title: '連携と取り込み',
              icon: Icons.link,
              children: [
                if (RecipeAiScope.maybeOf(context) case final scope?)
                  ListTile(
                    title: const Text('ChatGPT連携'),
                    leading: const Icon(Icons.link),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => RecipeAiSettingsScreen(session: scope),
                      ),
                    ),
                  ),
                AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) => ListTile(
                    key: const Key('select_inbox_folder_button'),
                    title: const Text('受け取りフォルダ'),
                    subtitle: Text(
                      controller.inboxFolder?.displayName ?? '未設定',
                    ),
                    leading: const Icon(Icons.folder_outlined),
                    enabled: !controller.isInboxBusy,
                    onTap: _selectInboxFolder,
                  ),
                ),
              ],
            ),
            RecipeSection(
              title: '料理とアプリ',
              icon: Icons.menu_book_outlined,
              children: [
                if (PreferenceControllerScope.maybeOf(context)
                    case final preferences?)
                  ListTile(
                    key: const Key('open_preferences'),
                    title: const Text('料理の好み'),
                    leading: const Icon(Icons.tune),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PreferenceScreen(
                          controller: preferences,
                          recipes: controller.recipes,
                        ),
                      ),
                    ),
                  ),
                ListTile(
                  key: const Key('app_information_button'),
                  title: const Text('このアプリについて'),
                  leading: const Icon(Icons.info_outline),
                  onTap: () => showAppInformationDialog(context),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
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
    final source = await showRecipePasteDialog(context);
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
      final issue = preparation.issue;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(preparation.message),
          duration: const Duration(seconds: 15),
          action: issue?.code == RecipeImportErrorCode.unsupportedSchemaVersion
              ? SnackBarAction(
                  label: 'アプリの更新を確認',
                  onPressed: () async {
                    try {
                      await openRecipeAppUpdates();
                    } catch (_) {}
                  },
                )
              : null,
        ),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecipeImportScreen(
          library: controller,
          preview: preparation.preview!,
        ),
      ),
    );
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
              '下の「レシピを作る」または「レシピを取り込む」から始めましょう。',
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
        leading: RecipePhotoAvatar(
          library: controller,
          recipeId: recipe.id,
          recipeTitle: recipe.title,
        ),
        title: Text(recipe.title, style: RecipeTheme.listRecipeTitle),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${recipe.servings}人分 ・ ${recipe.totalTimeMinutes}分'),
              const SizedBox(height: 6),
              RecipeDifficultyMeter(difficulty: recipe.estimatedDifficulty),
              if (!controller.isLatestRevision(recipe.id, recipe.revision))
                const Text('新しいバージョンがあります'),
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
            if (value == 'feedback') {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => FeedbackScreen(
                    recipeId: recipe.id,
                    controller: controller,
                  ),
                ),
              );
              return;
            }
            if (value == 'latest') {
              final latest = controller.latestRecipeFor(recipe.id);
              if (latest == null) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('最新のバージョンが見つかりません。')),
                  );
                }
                return;
              }
              final result = await controller.setActiveRevision(
                recipe.id,
                latest.revision,
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(result.message)));
              }
              return;
            }
            if (value != 'archive') return;
            final result = await controller.setArchived(recipe.id, true);
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(result)));
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem<String>(
              key: Key('recipe_feedback_${recipe.id}'),
              value: 'feedback',
              child: const Text('調理後の評価'),
            ),
            PopupMenuItem<String>(
              key: Key('activate_latest_recipe_${recipe.id}'),
              value: 'latest',
              enabled: !controller.isLatestRevision(recipe.id, recipe.revision),
              child: const Text('最新のバージョンに変更'),
            ),
            const PopupMenuItem<String>(
              value: 'archive',
              child: Text('アーカイブへ移す'),
            ),
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
              padding: const EdgeInsets.all(16),
              itemCount: controller.archivedRecipes.length,
              itemBuilder: (context, index) {
                final recipe = controller.archivedRecipes[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: const Icon(Icons.menu_book_outlined),
                    key: Key('archived_recipe_${recipe.id}'),
                    title: Text(recipe.title),
                    subtitle: Text('使用中のバージョン ${recipe.revision}'),
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
                              '「${recipe.title}」の全バージョン、タグ、事前準備、調理履歴と評価を端末から削除します。元に戻せません。\n\nGoogle DriveのInboxに元ファイルが残っている場合、次の確認で再取込されます。先にDrive側の元ファイルを取り除いてください。',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, false),
                                child: const Text('キャンセル'),
                              ),
                              FilledButton(
                                key: const Key(
                                  'confirm_delete_archived_recipe',
                                ),
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
                  ),
                );
              },
            ),
    ),
  );
}
