import 'package:flutter/material.dart';

import '../domain/cooking_profile.dart';
import '../domain/preference_candidate.dart';
import '../domain/recipe_document.dart';

class ExplicitPreferenceChoice {
  const ExplicitPreferenceChoice(
    this.scope,
    this.dimension,
    this.direction,
    this.declaration,
  );
  final PreferenceScope scope;
  final String dimension;
  final int direction;
  final String declaration;
}

class ExplicitPreferenceDialog extends StatefulWidget {
  const ExplicitPreferenceDialog({
    required this.profile,
    required this.labels,
    this.recipes = const [],
    super.key,
  });
  final CookingProfile profile;
  final Map<String, String> labels;
  final List<RecipeDocument> recipes;
  @override
  State<ExplicitPreferenceDialog> createState() =>
      _ExplicitPreferenceDialogState();
}

class _ExplicitPreferenceDialogState extends State<ExplicitPreferenceDialog> {
  final category = TextEditingController();
  final declaration = TextEditingController();
  PreferenceScopeKind kind = PreferenceScopeKind.global;
  String dimension = 'saltiness';
  int direction = -1;
  String? recipeId;
  String? error;
  @override
  void dispose() {
    category.dispose();
    declaration.dispose();
    super.dispose();
  }

  PreferenceScope get scope => PreferenceScope(kind, switch (kind) {
    PreferenceScopeKind.global => '*',
    PreferenceScopeKind.category => category.text.trim(),
    PreferenceScopeKind.recipe => recipeId ?? '',
  });
  void submit() {
    if (scope.value.isEmpty || declaration.text.trim().isEmpty) {
      setState(() => error = '対象と、好みの説明を入力してください。');
      return;
    }
    Navigator.pop(
      context,
      ExplicitPreferenceChoice(
        scope,
        dimension,
        direction,
        declaration.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final previous = (widget.profile.toJson()['preferences'] as List)
        .where(
          (p) =>
              p['scope']['kind'] == kind.name &&
              p['scope']['value'] == scope.value &&
              p['dimension'] == dimension,
        )
        .firstOrNull;
    final recipes = {for (final r in widget.recipes) r.id: r.title};
    return AlertDialog(
      title: const Text('自分の好みを登録'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('普段の好みを自分で指定します。評価の回数に関係なく、確認した内容を端末に登録します。'),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DropdownButtonFormField<PreferenceScopeKind>(
                isExpanded: true,
                itemHeight: null,
                key: const Key('explicit_preference_scope'),
                initialValue: kind,
                decoration: const InputDecoration(labelText: '対象'),
                items: [
                  const DropdownMenuItem(
                    value: PreferenceScopeKind.global,
                    child: Text('全料理'),
                  ),
                  const DropdownMenuItem(
                    value: PreferenceScopeKind.category,
                    child: Text('料理のカテゴリ'),
                  ),
                  if (recipes.isNotEmpty)
                    const DropdownMenuItem(
                      value: PreferenceScopeKind.recipe,
                      child: Text('このレシピ'),
                    ),
                ],
                onChanged: (value) => setState(() => kind = value!),
              ),
            ),
            if (kind == PreferenceScopeKind.category)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  key: const Key('explicit_preference_category'),
                  controller: category,
                  decoration: const InputDecoration(labelText: 'カテゴリ（例：主菜）'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            if (kind == PreferenceScopeKind.recipe)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  itemHeight: null,
                  key: const Key('explicit_preference_recipe'),
                  initialValue: recipeId,
                  decoration: const InputDecoration(labelText: 'レシピ'),
                  items: [
                    for (final entry in recipes.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: (value) => setState(() => recipeId = value),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                itemHeight: null,
                key: const Key('explicit_preference_dimension'),
                initialValue: dimension,
                decoration: const InputDecoration(labelText: '味や食感'),
                items: [
                  for (final entry in widget.labels.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
                onChanged: (value) => setState(() => dimension = value!),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DropdownButtonFormField<int>(
                isExpanded: true,
                itemHeight: null,
                key: const Key('explicit_preference_direction'),
                initialValue: direction,
                decoration: const InputDecoration(labelText: '希望'),
                items: const [
                  DropdownMenuItem(value: -1, child: Text('控えめに')),
                  DropdownMenuItem(value: 1, child: Text('強めに')),
                ],
                onChanged: (value) => setState(() => direction = value!),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                key: const Key('explicit_preference_declaration'),
                controller: declaration,
                maxLength: 2000,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: '好みの説明',
                  hintText: '例：普段から塩味が控えめな料理が好き',
                ),
              ),
            ),
            Text(
              '現在：${previous == null
                  ? '未登録'
                  : previous['direction'] == -1
                  ? '控えめ'
                  : '強め'} → 登録後：${direction == -1 ? '控えめ' : '強め'}',
            ),
            if (error != null) Text(error!),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('戻る'),
        ),
        FilledButton(
          key: const Key('confirm_explicit_preference'),
          onPressed: submit,
          child: const Text('この内容で登録'),
        ),
      ],
    );
  }
}
