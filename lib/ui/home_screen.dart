import 'package:flutter/material.dart';

import '../application/recipe_library_controller.dart';
import '../domain/recipe_document.dart';
import 'recipe_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.controller, super.key});

  final RecipeLibraryController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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
      appBar: AppBar(title: const Text('レシピ')),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                  child: FilledButton.icon(
                    key: const Key('import_recipe_button'),
                    onPressed: controller.isImporting
                        ? null
                        : () => _importRecipe(context),
                    icon: controller.isImporting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.file_open_outlined),
                    label: Text(
                      controller.isImporting ? '読み込み中…' : 'ChatGPTレシピを取り込む',
                    ),
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
    final result = await controller.importFromFile();
    if (!context.mounted || result.status == RecipeImportStatus.cancelled) {
      return;
    }

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
      child: Padding(
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
                '難易度${recipe.estimatedDifficulty} ・ Version ${recipe.revision}',
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
        trailing: const Icon(Icons.chevron_right),
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
