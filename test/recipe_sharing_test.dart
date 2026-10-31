import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_cooking_navigator/application/recipe_library_controller.dart';
import 'package:recipe_cooking_navigator/data/recipe_document_store.dart';
import 'package:recipe_cooking_navigator/data/recipe_tag_store.dart';
import 'package:recipe_cooking_navigator/domain/recipe_validator.dart';
import 'package:recipe_cooking_navigator/platform/ai_request_platform.dart';
import 'package:recipe_cooking_navigator/ui/recipe_detail_screen.dart';
import 'package:recipe_cooking_navigator/ui/recipe_sharing.dart';
import 'package:recipe_cooking_navigator/ui/recipe_theme.dart';
import 'package:recipe_cooking_navigator/ui/recipe_version_history_screen.dart';

class _Recipes implements RecipeDocumentStore {
  _Recipes(this.documents);
  final List<Map<String, dynamic>> documents;
  int writes = 0;
  @override
  Future<List<Map<String, dynamic>>> loadDocuments() async => documents;
  @override
  Future<StoreRecipeResult> saveDocument(Map<String, dynamic> document) async {
    writes++;
    return StoreRecipeResult.added;
  }
}

class _Tags implements RecipeTagStore {
  @override
  Future<Map<String, List<String>>> loadTags() async => {};
  @override
  Future<void> saveTags(String recipeId, List<String> tags) async {}
}

class _Platform implements AiRequestPlatform {
  bool fail = false;
  final sent = <String>[];
  @override
  Future<void> share(String request) async {
    if (fail) throw StateError('unavailable');
    sent.add(request);
  }

  @override
  Future<void> openChatGpt() async => throw StateError('must not open');
}

void main() {
  late RecipeValidator validator;
  late Map<String, dynamic> first;
  late Map<String, dynamic> latest;
  late _Recipes store;
  late RecipeLibraryController library;
  String? copied;

  setUpAll(() async {
    validator = RecipeValidator.fromSchemaString(
      await File('schemas/recipe-v2.schema.json').readAsString(),
    );
    first = jsonDecode(
      await File('examples/recipe-example.json').readAsString(),
    ) as Map<String, dynamic>;
    latest = jsonDecode(jsonEncode(first)) as Map<String, dynamic>;
    latest['recipe']['revision'] = 3;
    latest['recipe']['parent_revision'] = 1;
  });

  Future<void> initialize() async {
    store = _Recipes([first, latest]);
    library = RecipeLibraryController(
      store,
      _Tags(),
      validator,
      () async => null,
    );
    await library.load();
    addTearDown(library.dispose);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    copied = null;
  }

  testWidgets(
    'two-tap export preserves displayed past revision and approved theme',
    (tester) async {
      await initialize();
      final recipe = library.revisionFor(first['recipe']['id'] as String, 1)!;
      final cookingBefore = await library.cookingStore.read();
      await tester.pumpWidget(
        MaterialApp(
          theme: RecipeTheme.light,
          home: RecipeDetailScreen(
            recipe: recipe,
            controller: library,
            showExactRevision: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(RecipeDetailScreen)))
            .scaffoldBackgroundColor,
        RecipeTheme.cream,
      );
      await tester.tap(find.byKey(const Key('share_recipe')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('レシピをコピー'));
      await tester.pumpAndSettle();
      expect(jsonDecode(copied!), first);
      expect(library.activeRecipeFor(recipe.id)!.revision, 3);
      expect(await library.cookingStore.read(), cookingBefore);
      expect(find.byType(RecipeDetailScreen), findsOneWidget);
      expect(store.writes, 0);
    },
  );

  testWidgets(
    'history copies its browsed version without changing comparison or active',
    (tester) async {
      await initialize();
      final id = first['recipe']['id'] as String;
      await tester.pumpWidget(
        MaterialApp(
          theme: RecipeTheme.light,
          home: RecipeVersionHistoryScreen(
            recipeId: id,
            controller: library,
            initialRevision: 1,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('share_history_recipe')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('レシピをコピー'));
      await tester.pumpAndSettle();
      expect(jsonDecode(copied!), first);
      expect(library.activeRecipeFor(id)!.revision, 3);
      expect(find.byKey(const Key('recipe_revision_1')), findsOneWidget);
      expect(store.writes, 0);
    },
  );

  testWidgets(
    'plain sharing retries safely without requiring or saving evaluation',
    (tester) async {
      await initialize();
      final platform = _Platform()..fail = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: RecipeTheme.light,
          home: Scaffold(
            appBar: AppBar(
              actions: [
                RecipeShareMenu(
                  recipe: validator.validateDocument(first),
                  platform: platform,
                ),
              ],
            ),
          ),
        ),
      );
      for (final fail in [true, false]) {
        platform.fail = fail;
        await tester.tap(find.byType(RecipeShareMenu));
        await tester.pumpAndSettle();
        await tester.tap(find.text('レシピを共有'));
        await tester.pumpAndSettle();
        expect(platform.sent, fail ? isEmpty : hasLength(1));
      }
      expect(jsonDecode(platform.sent.single), first);
      expect((await library.cookingStore.read())['sessions'], isEmpty);
      expect(store.writes, 0);
    },
  );
}
