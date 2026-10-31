import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_cooking_navigator/application/kitchen_controller.dart';
import 'package:recipe_cooking_navigator/application/recipe_library_controller.dart';
import 'package:recipe_cooking_navigator/data/cooking_store.dart';
import 'package:recipe_cooking_navigator/data/preparation_checklist_store.dart';
import 'package:recipe_cooking_navigator/data/recipe_document_store.dart';
import 'package:recipe_cooking_navigator/data/recipe_inbox_state_store.dart';
import 'package:recipe_cooking_navigator/data/recipe_tag_store.dart';
import 'package:recipe_cooking_navigator/data/recipe_version_state_store.dart';
import 'package:recipe_cooking_navigator/domain/recipe_inbox.dart';
import 'package:recipe_cooking_navigator/domain/kitchen_timer.dart';
import 'package:recipe_cooking_navigator/domain/recipe_validator.dart';
import 'package:recipe_cooking_navigator/domain/session_assessment.dart';
import 'package:recipe_cooking_navigator/main.dart';
import 'package:recipe_cooking_navigator/platform/feedback_share_platform.dart';
import 'package:recipe_cooking_navigator/platform/recipe_share_platform.dart';
import 'package:recipe_cooking_navigator/ui/cooking_entry.dart';
import 'package:recipe_cooking_navigator/ui/cooking_screen.dart';
import 'package:recipe_cooking_navigator/ui/feedback_screen.dart';
import 'package:recipe_cooking_navigator/ui/kitchen_scope.dart';
import 'package:recipe_cooking_navigator/ui/recipe_detail_screen.dart';
import 'package:recipe_cooking_navigator/ui/recipe_version_history_screen.dart';
import 'package:recipe_cooking_navigator/ui/recipe_theme.dart';
import 'package:recipe_cooking_navigator/ui/home_screen.dart';
import 'package:recipe_cooking_navigator/ui/recipe_difficulty_meter.dart';
import 'package:recipe_cooking_navigator/ui/recipe_changes_card.dart';
import 'package:recipe_cooking_navigator/ui/recipe_compared_text.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String schemaSource;
  late String recipeSource;
  late List<MethodCall> cookingCalls;

  setUpAll(() async {
    schemaSource = await File('schemas/recipe-v2.schema.json').readAsString();
    recipeSource = await File('examples/recipe-example.json').readAsString();
  });

  setUp(() {
    // Do not reuse schema Futures created in a previous widget's fake zone.
    rootBundle.evict('schemas/recipe-v2.schema.json');
    rootBundle.evict('schemas/feedback-v2.schema.json');
    cookingCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('recipe/cooking'), (
          call,
        ) async {
          cookingCalls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('recipe/cooking'), null);
  });

  testWidgets('imports a recipe, lists it, and opens its details', (
    tester,
  ) async {
    final controller = RecipeLibraryController(
      _MemoryRecipeDocumentStore(),
      _MemoryRecipeTagStore(),
      RecipeValidator.fromSchemaString(schemaSource),
      () async => recipeSource,
    );
    await controller.load();

    await tester.pumpWidget(RecipeCookingNavigatorApp(controller: controller));

    expect(find.text('まだレシピがありません'), findsOneWidget);
    await tester.tap(find.byKey(const Key('open_recipe_import')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('import_recipe_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('レシピの内容確認'), findsOneWidget);
    expect(
      find.byKey(const Key('recipe_import_preview_title')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('confirm_recipe_import')));
    await tester.pumpAndSettle();

    expect(find.text('豚の生姜焼き'), findsOneWidget);
    expect(find.textContaining('2人分'), findsWidgets);

    expect(find.text('レシピ詳細'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('豚こま切れ肉'), 300);
    expect(find.text('材料'), findsOneWidget);
    expect(find.text('豚こま切れ肉'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('全体工程'), 300);
    expect(find.text('全体工程'), findsOneWidget);
  });

  testWidgets('archives a recipe from the list and restores it', (
    tester,
  ) async {
    final controller = RecipeLibraryController(
      _MemoryRecipeDocumentStore([
        jsonDecode(recipeSource) as Map<String, dynamic>,
      ]),
      _MemoryRecipeTagStore(),
      RecipeValidator.fromSchemaString(schemaSource),
      () async => null,
    );
    await controller.load();
    await tester.pumpWidget(RecipeCookingNavigatorApp(controller: controller));
    expect(find.text('豚の生姜焼き'), findsOneWidget);
    expect(find.text('キッチンツールを開く'), findsOneWidget);
    expect(find.text('表示: 保存中 ▾'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'キッチンツールを開く'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'アーカイブ'), findsOneWidget);

    await tester.tap(find.byTooltip('レシピの操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('アーカイブへ移す'));
    await tester.pumpAndSettle();
    expect(controller.recipes, isEmpty);
    expect(controller.archivedRecipes, hasLength(1));

    await tester.tap(find.byKey(const Key('open_recipe_archive')));
    await tester.pumpAndSettle();
    expect(find.text('豚の生姜焼き'), findsOneWidget);
    await tester.tap(find.byTooltip('アーカイブの操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('一覧へ戻す'));
    await tester.pumpAndSettle();
    expect(controller.recipes, hasLength(1));
    expect(controller.archivedRecipes, isEmpty);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('レシピの操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('アーカイブへ移す'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open_recipe_archive')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('アーカイブの操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完全削除'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Google DriveのInboxに元ファイル'), findsOneWidget);
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(controller.archivedRecipes, hasLength(1));
  });

  testWidgets(
    'home menu opens the recipe assessment without changing history',
    (tester) async {
      final first = jsonDecode(recipeSource) as Map<String, dynamic>;
      final second = jsonDecode(recipeSource) as Map<String, dynamic>;
      (second['recipe'] as Map)
        ..['revision'] = 2
        ..['parent_revision'] = 1;
      final validator = RecipeValidator.fromSchemaString(schemaSource);
      final base = validator.validateSource(recipeSource);
      final cooking = CookingStore();
      await cooking.startCooking(base, base.contextFor(2), 'step-onion');
      await cooking.complete(base.id, 1);
      final before = await cooking.read();
      final controller = RecipeLibraryController(
        _MemoryRecipeDocumentStore([first, second]),
        _MemoryRecipeTagStore(),
        validator,
        () async => null,
        cookingStore: cooking,
      );
      await controller.load();
      await tester.pumpWidget(
        RecipeCookingNavigatorApp(controller: controller),
      );
      await tester.tap(find.byTooltip('レシピの操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('recipe_feedback_${base.id}')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FeedbackScreen>(find.byType(FeedbackScreen)).recipeId,
        base.id,
      );
      expect(find.text('調理後の評価'), findsOneWidget);
      expect(controller.activeRecipeFor(base.id)!.revision, 2);
      expect(await cooking.read(), before);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets(
    'details show preparation before cooking and assessment actions',
    (tester) async {
      final controller = RecipeLibraryController(
        _MemoryRecipeDocumentStore([
          jsonDecode(recipeSource) as Map<String, dynamic>,
        ]),
        _MemoryRecipeTagStore(),
        RecipeValidator.fromSchemaString(schemaSource),
        () async => null,
      );
      await controller.load();
      await tester.pumpWidget(
        MaterialApp(
          theme: RecipeTheme.light,
          home: RecipeDetailScreen(
            recipe: controller.recipes.single,
            controller: controller,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('start_cooking')).hitTestable(),
        findsNothing,
      );
      expect(
        find.byKey(const Key('open_feedback')).hitTestable(),
        findsNothing,
      );
      expect(find.byType(RecipeDifficultyMeter), findsOneWidget);
      expect(find.text('使用中のバージョン 1'), findsOneWidget);
      final scrollable = find.byType(Scrollable).first;
      for (final heading in ['材料', '器具', '事前準備', '全体工程']) {
        await tester.scrollUntilVisible(
          find.text(heading),
          200,
          scrollable: scrollable,
        );
        await tester.pumpAndSettle();
        expect(find.text(heading).hitTestable(), findsOneWidget);
      }
      await tester.scrollUntilVisible(
        find.byKey(const Key('start_cooking')),
        200,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('start_cooking')).hitTestable(),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('open_feedback')),
        200,
        scrollable: scrollable,
      );
      await tester.tap(find.byKey(const Key('open_feedback')));
      await tester.pumpAndSettle();
      expect(find.byType(FeedbackScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets('switches to the saved latest recipe from the home menu', (
    tester,
  ) async {
    final revisionOne = jsonDecode(recipeSource) as Map<String, dynamic>;
    final revisionTwo = jsonDecode(recipeSource) as Map<String, dynamic>;
    final recipeId =
        (revisionOne['recipe'] as Map<String, dynamic>)['id'] as String;
    final recipeTwo = revisionTwo['recipe'] as Map<String, dynamic>;
    recipeTwo['revision'] = 2;
    recipeTwo['parent_revision'] = 1;
    recipeTwo['title'] = '豚の生姜焼き 改良版';

    final versionStore = _QuickSwitchVersionStore({recipeId: 1});
    final cookingStore = CookingStore();
    final controller = RecipeLibraryController(
      _MemoryRecipeDocumentStore([revisionOne, revisionTwo]),
      _MemoryRecipeTagStore(),
      RecipeValidator.fromSchemaString(schemaSource),
      () async => null,
      recipeVersionStateStore: versionStore,
      cookingStore: cookingStore,
    );
    await controller.load();
    final base = controller.revisionFor(recipeId, 1)!;
    await cookingStore.startCooking(
      base,
      base.contextFor(base.servings),
      base.steps.first['id'] as String,
    );
    final cookingBefore = await cookingStore.read();
    await tester.pumpWidget(RecipeCookingNavigatorApp(controller: controller));

    final latestAction = find.byKey(Key('activate_latest_recipe_$recipeId'));
    expect(find.text('豚の生姜焼き'), findsOneWidget);
    await tester.tap(find.byTooltip('レシピの操作'));
    await tester.pumpAndSettle();
    expect(tester.widget<PopupMenuItem<String>>(latestAction).enabled, isTrue);
    await tester.tap(latestAction);
    await tester.pumpAndSettle();

    expect(controller.activeRecipeFor(recipeId)?.revision, 2);
    expect(controller.revisionsFor(recipeId), hasLength(2));
    expect(await versionStore.loadActiveRevisions(), {recipeId: 2});
    expect(await cookingStore.read(), cookingBefore);
    expect(versionStore.writes, 1);
    expect(find.text('豚の生姜焼き 改良版'), findsOneWidget);

    await tester.tap(find.byTooltip('レシピの操作'));
    await tester.pumpAndSettle();
    expect(tester.widget<PopupMenuItem<String>>(latestAction).enabled, isFalse);
    await tester.tap(latestAction);
    await tester.pumpAndSettle();
    expect(versionStore.writes, 1);
    await tester.tap(find.text('アーカイブへ移す'));
    await tester.pumpAndSettle();
    expect(controller.archivedRecipes, hasLength(1));
  });

  testWidgets(
    'failed latest switch keeps the displayed and saved active recipe',
    (tester) async {
      final first = jsonDecode(recipeSource) as Map<String, dynamic>;
      final second = jsonDecode(recipeSource) as Map<String, dynamic>;
      final id = (first['recipe'] as Map)['id'] as String;
      (second['recipe'] as Map)
        ..['revision'] = 2
        ..['parent_revision'] = 1
        ..['title'] = '保存しない改良版';
      final versions = _QuickSwitchVersionStore({id: 1})..fail = true;
      final documents = _MemoryRecipeDocumentStore([first, second]);
      final controller = RecipeLibraryController(
        documents,
        _MemoryRecipeTagStore(),
        RecipeValidator.fromSchemaString(schemaSource),
        () async => null,
        recipeVersionStateStore: versions,
      );
      await controller.load();
      await tester.pumpWidget(
        RecipeCookingNavigatorApp(controller: controller),
      );
      await tester.tap(find.byTooltip('レシピの操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('activate_latest_recipe_$id')));
      await tester.pumpAndSettle();
      expect(find.text('切替の保存に失敗しました。'), findsOneWidget);
      expect(find.text('豚の生姜焼き'), findsOneWidget);
      expect(find.text('保存しない改良版'), findsNothing);
      expect(controller.activeRecipeFor(id)!.revision, 1);
      expect(await versions.loadActiveRevisions(), {id: 1});
      expect(controller.revisionsFor(id), hasLength(2));
      expect(documents.documents, [first, second]);
      controller.dispose();
    },
  );

  testWidgets('shared recipe uses the same validation and confirmation', (
    tester,
  ) async {
    final store = _MemoryRecipeDocumentStore();
    final controller = RecipeLibraryController(
      store,
      _MemoryRecipeTagStore(),
      RecipeValidator.fromSchemaString(schemaSource),
      () async => null,
    );
    await controller.load();
    final share = _FakeRecipeSharePlatform();
    await tester.pumpWidget(
      RecipeCookingNavigatorApp(controller: controller, sharePlatform: share),
    );
    await tester.pump();

    share.add(recipeSource);
    await tester.pumpAndSettle();
    expect(find.text('レシピの内容確認'), findsOneWidget);
    expect((await store.loadDocuments()), isEmpty);
    share.add(recipeSource);
    await tester.tap(find.byKey(const Key('cancel_recipe_import')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('discard_recipe_import')));
    await tester.pumpAndSettle();
    expect(find.text('レシピの内容確認'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cancel_recipe_import')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('discard_recipe_import')));
    await tester.pumpAndSettle();
    expect((await store.loadDocuments()), isEmpty);

    share.add('{broken');
    await tester.pumpAndSettle();
    expect(find.text('レシピの内容確認'), findsNothing);
    expect((await store.loadDocuments()), isEmpty);

    share.add(recipeSource);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_recipe_import')));
    await tester.pumpAndSettle();
    expect((await store.loadDocuments()), hasLength(1));
    expect(find.text('豚の生姜焼き'), findsOneWidget);
  });

  testWidgets('preparation checks persist without changing Recipe data', (
    tester,
  ) async {
    final original = jsonDecode(recipeSource) as Map<String, dynamic>;
    final store = _MemoryRecipeDocumentStore([original]);
    final checklist = PreparationChecklistStore();
    final controller = RecipeLibraryController(
      store,
      _MemoryRecipeTagStore(),
      RecipeValidator.fromSchemaString(schemaSource),
      () async => null,
      preparationStore: checklist,
    );
    await controller.load();
    await tester.pumpWidget(RecipeCookingNavigatorApp(controller: controller));
    await tester.tap(find.text('豚の生姜焼き'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('preparation_prep-onion')),
      300,
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('preparation_prep-onion')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(await checklist.checked('ginger-pork-001', 1), {'prep-onion'});
    expect(
      jsonEncode((await store.loadDocuments()).single),
      jsonEncode(original),
    );

    Navigator.of(tester.element(find.text('事前準備'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('豚の生姜焼き'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('preparation_prep-onion')),
      300,
    );
    final tile = tester.widget<CheckboxListTile>(
      find.byKey(const Key('preparation_prep-onion')),
    );
    expect(tile.value, isTrue);
  });

  testWidgets(
    'swipe browses history; explicit activation preserves cooking progress',
    (tester) async {
      final first = jsonDecode(recipeSource) as Map<String, dynamic>;
      final second = jsonDecode(recipeSource) as Map<String, dynamic>;
      second['recipe']['revision'] = 2;
      second['recipe']['parent_revision'] = 1;
      second['recipe']['title'] = '改善した生姜焼き';
      final id = first['recipe']['id'] as String;
      final versions = MemoryRecipeVersionStateStore({id: 2});
      final cooking = CookingStore();
      final controller = RecipeLibraryController(
        _MemoryRecipeDocumentStore([first, second]),
        _MemoryRecipeTagStore(),
        RecipeValidator.fromSchemaString(schemaSource),
        () async => null,
        recipeVersionStateStore: versions,
        cookingStore: cooking,
      );
      await controller.load();
      final base = controller.revisionFor(id, 1)!;
      await cooking.startCooking(
        base,
        base.contextFor(2),
        base.steps[0]['id'] as String,
      );
      final progress = jsonEncode(await cooking.read());
      await tester.pumpWidget(
        MaterialApp(
          theme: RecipeTheme.light,
          home: RecipeDetailScreen(
            recipe: controller.activeRecipeFor(id)!,
            controller: controller,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('改善前後の比較'), findsOneWidget);
      await tester.drag(
        find.byKey(const Key('recipe_revision_swipe')),
        const Offset(180, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('豚の生姜焼き'), findsOneWidget);
      expect(find.text('表示中のバージョン 1'), findsOneWidget);
      expect(controller.activeRecipeFor(id)!.revision, 2);
      expect(jsonEncode(await cooking.read()), progress);
      await tester.scrollUntilVisible(
        find.byKey(const Key('use_displayed_recipe')),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('use_displayed_recipe')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      expect(controller.activeRecipeFor(id)!.revision, 2);
      await tester.tap(find.byKey(const Key('use_displayed_recipe')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_future_recipe')));
      await tester.pumpAndSettle();
      expect(controller.activeRecipeFor(id)!.revision, 1);
      expect(jsonEncode(await cooking.read()), progress);
      final reloaded = RecipeLibraryController(
        _MemoryRecipeDocumentStore([first, second]),
        _MemoryRecipeTagStore(),
        RecipeValidator.fromSchemaString(schemaSource),
        () async => null,
        recipeVersionStateStore: versions,
      );
      await reloaded.load();
      expect(reloaded.activeRecipeFor(id)!.revision, 1);
      expect(controller.revisionsFor(id), hasLength(2));
    },
  );

  testWidgets('shows version history and uses the selected active revision', (
    tester,
  ) async {
    final revisionOne = jsonDecode(recipeSource) as Map<String, dynamic>;
    final revisionTwo = jsonDecode(recipeSource) as Map<String, dynamic>;
    final recipeTwo = revisionTwo['recipe'] as Map<String, dynamic>;
    recipeTwo['revision'] = 2;
    recipeTwo['parent_revision'] = 1;
    recipeTwo['title'] = '豚の生姜焼き 改良版';
    final recipeId =
        (revisionOne['recipe'] as Map<String, dynamic>)['id'] as String;
    final firstStepId =
        ((((revisionOne['recipe'] as Map<String, dynamic>)['stages'] as List)
                            .first
                        as Map<String, dynamic>)['steps']
                    as List)
                .cast<Map<String, dynamic>>()
                .first['id']
            as String;
    final cookingStore = CookingStore();
    final controller = RecipeLibraryController(
      _MemoryRecipeDocumentStore([revisionOne, revisionTwo]),
      _MemoryRecipeTagStore(),
      RecipeValidator.fromSchemaString(schemaSource),
      () async => null,
      cookingStore: cookingStore,
      recipeVersionStateStore: MemoryRecipeVersionStateStore({recipeId: 1}),
    );
    await controller.load();
    final savedRecipe = controller.revisionFor(recipeId, 1)!;
    await cookingStore.startCooking(
      savedRecipe,
      savedRecipe.contextFor(savedRecipe.servings),
      firstStepId,
    );
    await cookingStore.markHelpSeen();
    await tester.pumpWidget(RecipeCookingNavigatorApp(controller: controller));

    expect(find.text('豚の生姜焼き'), findsOneWidget);
    expect(find.text('新しいバージョンがあります'), findsOneWidget);
    await tester.tap(find.text('豚の生姜焼き'));
    await tester.pumpAndSettle();

    expect(find.text('使用中のバージョン 1'), findsOneWidget);
    expect(find.text('最新のバージョン 2'), findsOneWidget);
    await tester.tap(find.byKey(const Key('open_version_history')));
    await tester.pumpAndSettle();

    expect(find.text('バージョン履歴'), findsOneWidget);
    expect(find.byKey(const Key('recipe_revision_2')), findsNothing);
    expect(find.byKey(const Key('recipe_revision_1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('next_recipe_revision')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recipe_revision_2')), findsOneWidget);
    expect(find.text('バージョン 1から改善したバージョン 2'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('activate_revision_2')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('activate_revision_2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_activate_revision_2')));
    await tester.pumpAndSettle();

    expect(controller.activeRecipeFor(recipeId)?.revision, 2);
    expect(
      tester
          .state<FormFieldState<int>>(
            find.byKey(const Key('history_comparison_base')),
          )
          .value,
      1,
    );
    var progress = (await cookingStore.read())['progress'] as Map;
    expect((progress[recipeId] as Map)['revision'], 1);
    await tester.tap(find.byTooltip('戻る'));
    await tester.pumpAndSettle();
    expect(find.text('豚の生姜焼き 改良版'), findsOneWidget);
    expect(find.text('使用中のバージョン 2'), findsOneWidget);
    expect(find.text('最新のバージョン 2'), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const Key('resume_cooking')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('調理途中です・バージョン 1'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('resume_cooking')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('resume_cooking')));
    await tester.pumpAndSettle();
    expect(find.text('豚の生姜焼き'), findsOneWidget);
    expect(find.text('豚の生姜焼き 改良版'), findsNothing);
    await tester.tap(find.byTooltip('調理を中断'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('中断する'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('start_cooking')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('start_cooking')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('start_cooking')));
    await tester.pumpAndSettle();
    if (find.byKey(const Key('begin_cooking_steps')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('begin_cooking_steps')));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const Key('confirm_restart_cooking')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('begin_cooking_steps')));
    await tester.pumpAndSettle();
    progress = (await cookingStore.read())['progress'] as Map;
    expect((progress[recipeId] as Map)['revision'], 2);
  });

  for (final width in [320.0, 412.0]) {
    testWidgets(
      'history keeps a selectable baseline while swiping old and new at $width with enlarged text',
      (tester) async {
        tester.view.physicalSize = Size(width, 1120);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final documents = [
          for (var revision = 1; revision <= 3; revision++)
            jsonDecode(recipeSource) as Map<String, dynamic>,
        ];
        for (var index = 0; index < documents.length; index++) {
          final recipe = documents[index]['recipe'] as Map;
          recipe['revision'] = index + 1;
          recipe['parent_revision'] = index == 0 ? null : index;
          recipe['title'] = '生姜焼きバージョン${index + 1}';
          recipe['stages'][0]['steps'][0]['timer_seconds'] = (index + 1) * 60;
        }
        final id = documents[0]['recipe']['id'] as String;
        final versions = MemoryRecipeVersionStateStore({id: 2});
        final cooking = CookingStore();
        final controller = RecipeLibraryController(
          _MemoryRecipeDocumentStore(documents),
          _MemoryRecipeTagStore(),
          RecipeValidator.fromSchemaString(schemaSource),
          () async => null,
          recipeVersionStateStore: versions,
          cookingStore: cooking,
        );
        await controller.load();
        final initialCooking = jsonEncode(await cooking.read());
        await tester.pumpWidget(
          MaterialApp(
            theme: RecipeTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: RecipeVersionHistoryScreen(
              recipeId: id,
              controller: controller,
              initialRevision: 3,
            ),
          ),
        );
        await tester.pumpAndSettle();
        RecipeChangesCard comparison() =>
            tester.widget<RecipeChangesCard>(find.byType(RecipeChangesCard));
        expect(comparison().comparison.beforeRevision, 2);
        expect(comparison().comparison.afterRevision, 3);
        expect(
          tester
              .state<FormFieldState<int>>(
                find.byKey(const Key('history_comparison_base')),
              )
              .value,
          2,
        );
        await tester.drag(
          find.byKey(const Key('recipe_revision_swipe')),
          const Offset(180, 0),
        );
        await tester.pumpAndSettle();
        expect(comparison().comparison.beforeRevision, 2);
        expect(comparison().comparison.afterRevision, 2);
        expect(comparison().comparison.changes, isEmpty);
        await tester.drag(
          find.byKey(const Key('recipe_revision_swipe')),
          const Offset(180, 0),
        );
        await tester.pumpAndSettle();
        expect(comparison().comparison.beforeRevision, 2);
        expect(comparison().comparison.afterRevision, 1);
        expect(
          comparison().comparison.changes.any(
            (change) => change.before == '120秒' && change.after == '60秒',
          ),
          isTrue,
        );
        final changesHeader = find.text(
          '変更点（${comparison().comparison.changes.length}項目）',
        );
        await tester.scrollUntilVisible(
          changesHeader,
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(changesHeader);
        await tester.pumpAndSettle();
        expect(find.text('120秒 → 60秒'), findsWidgets);
        expect(find.text('緑＝表示中・淡い赤＝比較元。基準人数同士で比較。'), findsOneWidget);
        await tester.tap(find.byKey(const Key('history_comparison_base')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('バージョン 1').last);
        await tester.pumpAndSettle();
        expect(comparison().comparison.beforeRevision, 1);
        expect(comparison().comparison.afterRevision, 1);
        await tester.tap(find.byKey(const Key('next_recipe_revision')));
        await tester.pumpAndSettle();
        expect(comparison().comparison.beforeRevision, 1);
        expect(comparison().comparison.afterRevision, 2);
        expect(controller.activeRecipeFor(id)!.revision, 2);
        expect(await versions.loadActiveRevisions(), {id: 2});
        expect(jsonEncode(await cooking.read()), initialCooking);
        for (var index = 0; index < 16; index++) {
          await tester.drag(find.byType(ListView), const Offset(0, -350));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        await tester.scrollUntilVisible(
          find.text('器具'),
          -250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('事前準備'), findsWidgets);
      },
    );
  }

  testWidgets(
    'detail jumps to changed steps and separates scaling from version changes',
    (tester) async {
      final original = jsonDecode(recipeSource) as Map<String, dynamic>;
      final changed = jsonDecode(recipeSource) as Map<String, dynamic>;
      final recipe = changed['recipe'] as Map;
      recipe['revision'] = 2;
      recipe['parent_revision'] = 1;
      recipe['amounts'][0]['quantity']['value']['numerator'] = 150;
      recipe['stages'][0]['steps'][0]['timer_seconds'] = 150;
      final id = recipe['id'] as String;
      final versions = MemoryRecipeVersionStateStore({id: 2});
      final cooking = CookingStore();
      final controller = RecipeLibraryController(
        _MemoryRecipeDocumentStore([original, changed]),
        _MemoryRecipeTagStore(),
        RecipeValidator.fromSchemaString(schemaSource),
        () async => null,
        recipeVersionStateStore: versions,
        cookingStore: cooking,
      );
      await controller.load();
      final progress = jsonEncode(await cooking.read());
      await tester.pumpWidget(
        MaterialApp(
          theme: RecipeTheme.light,
          home: RecipeDetailScreen(
            recipe: controller.activeRecipeFor(id)!,
            controller: controller,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('step_text_timer:step-onion')),
        findsNothing,
      );
      final chip = find.byKey(const ValueKey('change_section_調理の工程'));
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(find.text('詳しい工程を閉じる'), findsOneWidget);
      final timer = tester.widget<RecipeComparedText>(
        find.byKey(const ValueKey('step_text_timer:step-onion')),
      );
      expect(timer.compared, isTrue);
      expect(timer.before, '120秒');
      expect(timer.text, '150秒');
      final increase = find.byKey(const Key('increase_servings'));
      await tester.ensureVisible(increase);
      await tester.pumpAndSettle();
      await tester.tap(increase);
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) => widget is RecipeComparedText && widget.compared,
        ),
        findsNothing,
      );
      expect(await versions.loadActiveRevisions(), {id: 2});
      expect(jsonEncode(await cooking.read()), progress);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('opens feedback from a past version without activating it', (
    tester,
  ) async {
    final firstJson = jsonDecode(recipeSource) as Map<String, dynamic>;
    final secondJson = jsonDecode(recipeSource) as Map<String, dynamic>;
    final secondRecipe = secondJson['recipe'] as Map<String, dynamic>;
    secondRecipe['revision'] = 2;
    secondRecipe['parent_revision'] = 1;
    secondRecipe['title'] = '豚の生姜焼き 改良版';
    final recipeId =
        (firstJson['recipe'] as Map<String, dynamic>)['id'] as String;
    final cookingStore = CookingStore();
    final controller = RecipeLibraryController(
      _MemoryRecipeDocumentStore([firstJson, secondJson]),
      _MemoryRecipeTagStore(),
      RecipeValidator.fromSchemaString(schemaSource),
      () async => null,
      cookingStore: cookingStore,
    );
    await controller.load();
    final first = controller.revisionFor(recipeId, 1)!;
    await cookingStore.startCooking(
      first,
      first.contextFor(first.servings),
      'step-onion',
    );
    await cookingStore.complete(recipeId, 1);
    final cooked = controller.revisionFor(recipeId, 2)!;
    await cookingStore.startCooking(
      cooked,
      cooked.contextFor(cooked.servings),
      'step-onion',
    );
    await cookingStore.complete(recipeId, 2);
    final sessions = ((await cookingStore.read())['sessions'] as List)
        .cast<Map<String, dynamic>>();
    final firstSessionId =
        sessions.singleWhere(
              (session) => session['revision'] == 1,
            )['session_id']
            as String;
    final secondSessionId =
        sessions.singleWhere(
              (session) => session['revision'] == 2,
            )['session_id']
            as String;
    await cookingStore.saveAssessment(
      secondSessionId,
      const SessionAssessment(
        actualTimeMinutes: 20,
        difficultyScore: 2,
        difficultyComment: '',
        issues: [],
        changesMade: [],
        overall: 4,
        taste: [],
        comment: '',
        nextTimeIntent: [],
      ),
    );
    final sharedSources = <String>[];
    final sharedSignal = Completer<void>();
    const feedbackChannel = MethodChannel('recipe/feedback');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(feedbackChannel, (call) async {
      if (call.method != 'shareJson' || call.arguments is! String) {
        throw MissingPluginException(call.method);
      }
      sharedSources.add(call.arguments as String);
      if (!sharedSignal.isCompleted) sharedSignal.complete();
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(feedbackChannel, null),
    );
    await tester.pumpWidget(RecipeCookingNavigatorApp(controller: controller));

    await tester.tap(find.text('豚の生姜焼き 改良版'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open_version_history')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('previous_recipe_revision')));
    await tester.pumpAndSettle();
    final improve = find.byKey(const Key('improve_revision_1'));
    await tester.scrollUntilVisible(
      improve,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(improve);
    await tester.pumpAndSettle();

    expect(find.text('調理後の評価'), findsOneWidget);
    expect(
      tester
          .widget<DropdownButton<String>>(
            find.byKey(const Key('feedback_session')),
          )
          .value,
      secondSessionId,
    );
    expect(find.text(cooked.title), findsOneWidget);
    tester
        .widget<DropdownButton<String>>(
          find.byKey(const Key('feedback_session')),
        )
        .onChanged!(firstSessionId);
    await tester.pumpAndSettle();
    expect(find.text(first.title), findsOneWidget);
    expect(find.text(cooked.title), findsNothing);
    tester
        .widget<DropdownButton<String>>(
          find.byKey(const Key('feedback_session')),
        )
        .onChanged!(secondSessionId);
    await tester.pumpAndSettle();
    expect(find.text(cooked.title), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('feedback_improvement_revision')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester
          .widget<DropdownButton<int>>(
            find.byKey(const Key('feedback_improvement_revision')),
          )
          .value,
      1,
    );
    expect(controller.activeRecipeFor(recipeId)?.revision, 2);
    expect(controller.latestRecipeFor(recipeId)?.revision, 2);
    expect(controller.revisionsFor(recipeId), hasLength(2));
    await tester.scrollUntilVisible(
      find.byKey(const Key('feedback_goal')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const Key('feedback_goal')),
      'Version 1を基準に調整する',
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('share_feedback')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('share_feedback')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_share_feedback')));
    await tester.pumpAndSettle();
    await _pumpUntilFeedbackShared(tester, sharedSignal);
    await tester.pumpAndSettle();
    expect(find.text('共有画面を開きました。送信先を確認してください。'), findsWidgets);
    expect(sharedSources, hasLength(1));
    final feedback = jsonDecode(sharedSources.single) as Map<String, dynamic>;
    expect((feedback['recipe_snapshot'] as Map)['recipe']['revision'], 1);
    expect((feedback['cook_session'] as Map)['recipe_revision'], 2);
    expect((feedback['revision_request'] as Map)['next_revision'], 3);
  });

  testWidgets(
    'changes servings consistently and fixes them when cooking starts',
    (tester) async {
      final cookingStore = CookingStore();
      await cookingStore.markHelpSeen();
      final controller = RecipeLibraryController(
        _MemoryRecipeDocumentStore(),
        _MemoryRecipeTagStore(),
        RecipeValidator.fromSchemaString(schemaSource),
        () async => recipeSource,
        cookingStore: cookingStore,
      );
      await controller.load();
      await controller.importSource(recipeSource);
      await tester.pumpWidget(
        RecipeCookingNavigatorApp(controller: controller),
      );
      await tester.tap(find.text('豚の生姜焼き'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('increase_servings')),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('increase_servings')));
      await tester.tap(find.byKey(const Key('increase_servings')));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.byKey(const Key('selected_servings_chip')),
        -150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('4人分'), findsOneWidget);
      expect(find.textContaining('材料を4人分に換算'), findsOneWidget);

      await controller.setTags('ginger-pork-001', const ['夕食']);
      await tester.pump();
      expect(find.text('4人分'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const Key('start_cooking')),
        300,
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('start_cooking')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('start_cooking')));
      await tester.pumpAndSettle();
      if (find.byKey(const Key('begin_cooking_steps')).evaluate().isNotEmpty) {
        await tester.tap(find.byKey(const Key('begin_cooking_steps')));
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const Key('cooking_servings')), findsOneWidget);
      expect(find.text('4人分で調理中'), findsOneWidget);
      expect(find.textContaining('サラダ油 小さじ1'), findsWidgets);
      expect(find.textContaining('玉ねぎ 1個'), findsWidgets);

      final stored = await cookingStore.read();
      final progress = (stored['progress'] as Map)['ginger-pork-001'] as Map;
      expect((progress['cooking_context'] as Map)['target_servings'], 4);
    },
  );

  testWidgets('shows attribution and food safety notice', (tester) async {
    final controller = RecipeLibraryController(
      _MemoryRecipeDocumentStore(),
      _MemoryRecipeTagStore(),
      RecipeValidator.fromSchemaString(schemaSource),
      () async => null,
    );
    await controller.load();

    await tester.pumpWidget(RecipeCookingNavigatorApp(controller: controller));
    await tester.tap(find.byKey(const Key('open_settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('app_information_button')));
    await tester.pumpAndSettle();

    expect(find.text('このアプリについて'), findsWidgets);
    expect(find.text('安全に関する注意'), findsOneWidget);
    expect(find.textContaining('アレルギー'), findsOneWidget);
    expect(find.textContaining('Apache License 2.0'), findsOneWidget);
    expect(find.textContaining('Copyright 2026 kapioka'), findsOneWidget);
    expect(
      find.byKey(const Key('open_source_licenses_button')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('open_source_licenses_button')));
    await tester.pumpAndSettle();
    final pubspecSource = await tester.runAsync(
      () => File('pubspec.yaml').readAsString(),
    );
    final packageVersion = RegExp(
      r'^version:\s*([^+\s]+)',
      multiLine: true,
    ).firstMatch(pubspecSource!)!.group(1);
    expect(
      tester.widget<LicensePage>(find.byType(LicensePage)).applicationVersion,
      packageVersion,
    );
  });

  testWidgets('searches ingredients and saves searchable recipe tags', (
    tester,
  ) async {
    final controller = RecipeLibraryController(
      _MemoryRecipeDocumentStore(),
      _MemoryRecipeTagStore(),
      RecipeValidator.fromSchemaString(schemaSource),
      () async => recipeSource,
    );
    await controller.load();
    await tester.pumpWidget(RecipeCookingNavigatorApp(controller: controller));
    await tester.tap(find.byKey(const Key('open_recipe_import')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('import_recipe_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('confirm_recipe_import')));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('recipe_search_field')), 'こま');
    await tester.pump();
    expect(find.text('豚の生姜焼き'), findsOneWidget);
    expect(find.text('豚こま切れ肉'), findsOneWidget);
    expect(find.text('食材'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('recipe_search_field')),
      '一致しない',
    );
    await tester.pump();
    expect(find.textContaining('一致するレシピはありません'), findsOneWidget);

    await tester.tap(find.byKey(const Key('clear_recipe_search')));
    await tester.pump();
    await tester.tap(find.text('豚の生姜焼き'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit_recipe_tags_button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('recipe_tag_field_0')), '時短');
    await tester.tap(find.byKey(const Key('save_recipe_tags_button')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('時短'), 300);
    expect(find.text('時短'), findsOneWidget);

    await tester.tap(find.byTooltip('戻る'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('recipe_search_field')), '時');
    await tester.pump();
    expect(find.text('豚の生姜焼き'), findsOneWidget);
    expect(find.text('タグ'), findsOneWidget);
  });

  testWidgets('selects an Inbox and shows per-file import results', (
    tester,
  ) async {
    final inboxStateStore = _WidgetRecipeInboxStateStore();
    final controller = RecipeLibraryController(
      _MemoryRecipeDocumentStore(),
      _MemoryRecipeTagStore(),
      RecipeValidator.fromSchemaString(schemaSource),
      () async => null,
      recipeInboxPlatform: _WidgetRecipeInboxPlatform(
        RecipeInboxFile(
          documentId: 'widget-document',
          name: 'recipe.json',
          source: recipeSource,
          sha256: 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
        ),
      ),
      recipeInboxStateStore: inboxStateStore,
    );
    await controller.load();
    await tester.pumpWidget(RecipeCookingNavigatorApp(controller: controller));

    await tester.tap(find.byKey(const Key('open_recipe_import')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('check_recipe_inbox_button')));
    await tester.pumpAndSettle();
    expect(find.text('Inboxフォルダを選択'), findsOneWidget);

    await tester.tap(find.byKey(const Key('confirm_select_inbox_folder')));
    await tester.pumpAndSettle();

    expect(find.text('Inboxの確認結果'), findsOneWidget);
    expect(find.text('1件取り込み、0件保存済み、0件拒否しました。'), findsOneWidget);
    expect(find.text('recipe.json'), findsOneWidget);
    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();
    expect(find.text('豚の生姜焼き'), findsOneWidget);
    expect(controller.inboxFolder?.displayName, 'Inbox');
  });

  testWidgets('keeps file import enabled while Inbox check is pending', (
    tester,
  ) async {
    final pendingFiles = Completer<List<RecipeInboxFile>>();
    final inboxStateStore = _WidgetRecipeInboxStateStore(
      const RecipeInboxState(
        folder: RecipeInboxFolder(
          treeUri: 'content://provider/tree/inbox',
          displayName: 'Inbox',
        ),
        receipts: <RecipeInboxReceipt>[],
      ),
    );
    final controller = RecipeLibraryController(
      _MemoryRecipeDocumentStore(),
      _MemoryRecipeTagStore(),
      RecipeValidator.fromSchemaString(schemaSource),
      () async => recipeSource,
      recipeInboxPlatform: _BlockingWidgetRecipeInboxPlatform(
        pendingFiles.future,
      ),
      recipeInboxStateStore: inboxStateStore,
    );
    await controller.load();
    await tester.pumpWidget(RecipeCookingNavigatorApp(controller: controller));

    await tester.tap(find.byKey(const Key('open_recipe_import')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('check_recipe_inbox_button')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('open_recipe_import')));
    await tester.pumpAndSettle();
    final importButton = tester.widget<ListTile>(
      find.byKey(const Key('import_recipe_button')),
    );
    expect(importButton.enabled, isTrue);

    await tester.tap(find.byKey(const Key('import_recipe_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_recipe_import')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('豚の生姜焼き'), findsOneWidget);

    pendingFiles.complete(const <RecipeInboxFile>[]);
    await tester.pumpAndSettle();
    expect(find.text('Inboxの確認結果'), findsOneWidget);
  });

  testWidgets('navigates, resumes, times, and explicitly completes cooking', (
    tester,
  ) async {
    final document = jsonDecode(recipeSource) as Map<String, dynamic>;
    final recipe = document['recipe'] as Map<String, dynamic>;
    for (final stage in recipe['stages'] as List) {
      for (final step in stage['steps'] as List) {
        step['timer_seconds'] = 1;
      }
    }
    final cookingStore = CookingStore();
    final controller = RecipeLibraryController(
      _MemoryRecipeDocumentStore(),
      _MemoryRecipeTagStore(),
      RecipeValidator.fromSchemaString(schemaSource),
      () async => jsonEncode(document),
      cookingStore: cookingStore,
    );
    await controller.load();
    await tester.pumpWidget(RecipeCookingNavigatorApp(controller: controller));
    await tester.tap(find.byKey(const Key('open_recipe_import')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('import_recipe_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('confirm_recipe_import')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('豚の生姜焼き'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('start_cooking')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('start_cooking')));
    await tester.pumpAndSettle();
    if (find.byKey(const Key('begin_cooking_steps')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('begin_cooking_steps')));
      await tester.pumpAndSettle();
    }
    expect(find.text('画面操作の説明'), findsOneWidget);
    await tester.tap(find.text('調理画面へ戻る'));
    await tester.pumpAndSettle();
    expect(find.text('玉ねぎを炒める'), findsOneWidget);
    expect(find.byKey(const Key('complete_cooking')), findsNothing);

    final gesture = find.byKey(const Key('cooking_gesture'));
    var bounds = tester.getRect(gesture);
    await tester.tapAt(
      Offset(bounds.left + bounds.width * .85, bounds.center.dy),
    );
    await tester.pumpAndSettle();
    expect(find.text('豚肉を焼く'), findsOneWidget);

    expect(find.text('材料を見る'), findsOneWidget);
    expect(find.text('工程一覧'), findsOneWidget);
    expect(find.text('読み上げ'), findsOneWidget);
    expect(find.text('音声操作 OFF'), findsOneWidget);
    expect(find.byKey(const Key('screen_controls_button')), findsOneWidget);
    final previousRect = tester.getRect(
      find.byKey(const Key('previous_step_button')),
    );
    final controlsRect = tester.getRect(
      find.byKey(const Key('screen_controls_button')),
    );
    final nextRect = tester.getRect(find.byKey(const Key('next_step_button')));
    expect(previousRect.center.dy, controlsRect.center.dy);
    expect(controlsRect.center.dy, nextRect.center.dy);
    expect(previousRect.center.dx, lessThan(controlsRect.center.dx));
    expect(controlsRect.center.dx, lessThan(nextRect.center.dx));
    await tester.tap(find.byKey(const Key('screen_controls_button')));
    await tester.pumpAndSettle();
    expect(find.text('画面操作の説明'), findsOneWidget);
    await tester.tap(find.text('調理画面へ戻る'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('voice_state')));
    await tester.pumpAndSettle();
    expect(find.text('音声操作'), findsOneWidget);
    expect(find.byKey(const Key('voice_command_list')), findsOneWidget);
    expect(find.textContaining('次・次へ／戻る・前へ'), findsOneWidget);
    expect(find.textContaining('音声停止／読み上げ停止'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('screen_controls_help_button')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('screen_controls_help_button')));
    await tester.pumpAndSettle();
    expect(find.text('画面操作の説明'), findsOneWidget);
    await tester.tap(find.text('調理画面へ戻る'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('materials_button')));
    await tester.pumpAndSettle();
    expect(find.text('材料一覧'), findsOneWidget);
    await tester.tap(find.text('調理画面へ戻る'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('工程一覧'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('生姜だれを煮絡める'));
    await tester.pumpAndSettle();
    expect(find.text('生姜だれを煮絡める'), findsOneWidget);

    await tester.drag(gesture, const Offset(100, 0));
    await tester.pumpAndSettle();
    expect(find.text('豚肉を焼く'), findsOneWidget);

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const codec = StandardMethodCodec();
    await messenger.handlePlatformMessage(
      'recipe/cooking',
      codec.encodeMethodCall(const MethodCall('recognized', '次へ')),
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(find.text('生姜だれを煮絡める'), findsOneWidget);
    await messenger.handlePlatformMessage(
      'recipe/cooking',
      codec.encodeMethodCall(const MethodCall('recognized', '前へ')),
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(find.text('豚肉を焼く'), findsOneWidget);

    await tester.tap(find.byKey(const Key('speak_button')));
    await tester.pump();
    expect(find.text('読み上げ停止'), findsOneWidget);
    expect(cookingCalls.last.method, 'speak');
    await messenger.handlePlatformMessage(
      'recipe/cooking',
      codec.encodeMethodCall(const MethodCall('recognized', '音声停止')),
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(find.text('読み上げ'), findsOneWidget);
    expect(cookingCalls.last.method, 'stopSpeaking');

    await tester.tap(find.byKey(const Key('speak_button')));
    await tester.pump();
    await messenger.handlePlatformMessage(
      'recipe/cooking',
      codec.encodeMethodCall(const MethodCall('recognized', '読み上げ停止')),
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(find.text('読み上げ'), findsOneWidget);
    expect(cookingCalls.last.method, 'stopSpeaking');

    await tester.longPress(find.byKey(const Key('speak_button')));
    await tester.pumpAndSettle();
    expect(find.text('読み上げの詳細'), findsOneWidget);
    expect(find.byKey(const Key('restart_reading_button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('read_previous_step_button')));
    await tester.pumpAndSettle();
    expect(find.text('玉ねぎを炒める'), findsOneWidget);
    expect(cookingCalls.last.method, 'speak');

    await tester.longPress(find.byKey(const Key('speak_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('read_next_step_button')));
    await tester.pumpAndSettle();
    expect(find.text('豚肉を焼く'), findsOneWidget);
    expect(cookingCalls.last.method, 'speak');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('調理を中断しますか？'), findsOneWidget);
    await tester.tap(find.text('戻る'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('timer_button')));
    await tester.pumpAndSettle();
    expect(find.text('レシピの設定：1秒'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('timer_detail_seconds'))).data,
      '1秒',
    );
    await tester.tap(find.byKey(const Key('add_10_seconds')));
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('timer_detail_seconds'))).data,
      '11秒',
    );
    await tester.tap(find.byKey(const Key('reset_timer_adjustments')));
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('timer_detail_seconds'))).data,
      '1秒',
    );
    await tester.tap(find.byKey(const Key('add_10_seconds')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('timer_toggle_detail')));
    await tester.pump();
    expect(find.text('タイマー停止'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reset_timer_adjustments')));
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('timer_detail_seconds'))).data,
      '1秒',
    );
    await tester.tap(find.byKey(const Key('timer_toggle_detail')));
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('timer_detail_seconds'))).data,
      '1秒',
    );
    await tester.tap(find.byKey(const Key('timer_toggle_detail')));
    await tester.pump();
    await tester.tap(find.text('調理画面へ戻る'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('次へ'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1200)),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('生姜だれを煮絡める'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('timer_status'))).data,
      contains('タイマー終了'),
    );

    await tester.tap(find.byTooltip('調理を中断'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('中断する'));
    await tester.pumpAndSettle();
    expect(find.textContaining('調理途中です'), findsOneWidget);
    expect(find.textContaining('工程 3 / 3'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('resume_cooking')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('resume_cooking')));
    await tester.pumpAndSettle();
    expect(find.text('生姜だれを煮絡める'), findsOneWidget);
    expect(find.textContaining('調理画面の操作'), findsNothing);
    expect(find.byKey(const Key('next_step_button')), findsNothing);
    final beforeComplete = await cookingStore.read();
    await tester.tap(find.byKey(const Key('complete_cooking')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('戻る'));
    await tester.pumpAndSettle();
    expect(await cookingStore.read(), beforeComplete);
    await tester.tap(find.byKey(const Key('complete_cooking')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完了する'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('start_cooking')), findsOneWidget);
    expect(find.byKey(const Key('resume_cooking')), findsNothing);
    final saved = await cookingStore.read();
    expect(saved['progress'], isEmpty);
    expect(saved['sessions'], hasLength(1));
    expect(
      cookingCalls.map((call) => call.method),
      containsAll(<String>['wake', 'close', 'speak']),
    );
  });

  testWidgets(
    'preparation owns wake until back without replacing interrupted cooking',
    (tester) async {
      final store = CookingStore();
      final library = RecipeLibraryController(
        _MemoryRecipeDocumentStore([
          jsonDecode(recipeSource) as Map<String, dynamic>,
        ]),
        _MemoryRecipeTagStore(),
        RecipeValidator.fromSchemaString(schemaSource),
        () async => null,
        cookingStore: store,
      );
      await library.load();
      final recipe = library.recipes.single;
      await store.markHelpSeen();
      await store.startCooking(
        recipe,
        recipe.contextFor(3),
        recipe.steps[1]['id'] as String,
      );
      final previous = jsonEncode((await store.read())['progress']);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CookingEntry(
              recipe: recipe,
              controller: library,
              cookingContext: recipe.contextFor(2),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      cookingCalls.clear();
      await tester.tap(find.byKey(const Key('start_cooking')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_restart_cooking')));
      await tester.pumpAndSettle();
      expect(find.text('下準備'), findsOneWidget);
      expect(cookingCalls.map((c) => c.method), ['wake']);
      expect(jsonEncode((await store.read())['progress']), previous);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(cookingCalls.last.method, 'close');
      expect(jsonEncode((await store.read())['progress']), previous);
      await tester.tap(find.byKey(const Key('resume_cooking')));
      await tester.pumpAndSettle();
      expect(find.text('下準備'), findsNothing);
      expect(cookingCalls.last.method, 'wake');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(cookingCalls.last.method, 'close');
    },
  );

  testWidgets('uses persistent Kitchen timers for Recipe steps', (
    tester,
  ) async {
    final cookingStore = CookingStore();
    await cookingStore.markHelpSeen();
    final controller = RecipeLibraryController(
      _MemoryRecipeDocumentStore([
        jsonDecode(recipeSource) as Map<String, dynamic>,
      ]),
      _MemoryRecipeTagStore(),
      RecipeValidator.fromSchemaString(schemaSource),
      () async => null,
      cookingStore: cookingStore,
    );
    await controller.load();
    final recipe = controller.recipes.single;
    var clock = Duration.zero;
    final kitchen = KitchenController(now: () => clock)..open(foreground: true);
    addTearDown(kitchen.dispose);

    Future<bool> perform(void Function(KitchenController) operation) async {
      await kitchen.transact(operation, (_) async {});
      return true;
    }

    await tester.pumpWidget(
      MaterialApp(
        home: KitchenScope(
          controller: kitchen,
          perform: perform,
          child: Scaffold(
            body: SingleChildScrollView(
              child: CookingEntry(
                recipe: recipe,
                controller: controller,
                cookingContext: recipe.contextFor(recipe.servings),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('キッチンの共通タイマーを使って調理します。'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('start_cooking')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('start_cooking')));
    await tester.pumpAndSettle();
    if (find.byKey(const Key('begin_cooking_steps')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('begin_cooking_steps')));
      await tester.pumpAndSettle();
    }
    expect(find.byType(CookingScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('timer_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('timer_toggle_detail')));
    await tester.pump();

    expect(kitchen.timers, hasLength(1));
    final firstTimer = kitchen.timers.single;
    expect(firstTimer.configuredDuration, const Duration(seconds: 120));
    final source = firstTimer.source as RecipeStepTimerSource;
    expect(source.recipeId, recipe.id);
    expect(source.recipeRevision, recipe.revision);
    expect(source.stepId, 'step-onion');
    expect(source.recipeDisplayName, recipe.title);
    expect(source.stepDisplayName, '玉ねぎを炒める');

    await tester.tap(find.text('調理画面へ戻る'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('timer_status')), findsOneWidget);
    await tester.tap(find.byKey(const Key('next_step_button')));
    await tester.pumpAndSettle();
    expect(kitchen.timers.single.state, KitchenTimerState.running);
    expect(find.byKey(const Key('timer_status')), findsNothing);

    await tester.tap(find.byKey(const Key('previous_step_button')));
    await tester.pumpAndSettle();
    clock = const Duration(seconds: 20);
    kitchen.refreshDisplay();
    await tester.pump();
    expect(find.textContaining('残り 100秒'), findsOneWidget);

    final cookingData = jsonEncode(await cookingStore.read());
    expect(cookingData, isNot(contains(firstTimer.id)));
    expect(cookingData, isNot(contains('recipe_step')));
  });

  testWidgets('saves an assessment and shares validated Feedback on request', (
    tester,
  ) async {
    final validator = RecipeValidator.fromSchemaString(schemaSource);
    final recipe = validator.validateSource(recipeSource);
    final cookingStore = CookingStore(null, validator);
    await cookingStore.startCooking(recipe, recipe.contextFor(3), 'step-onion');
    await cookingStore.complete(recipe.id, recipe.revision);
    final session =
        ((await cookingStore.read())['sessions'] as List).single
            as Map<String, dynamic>;
    await cookingStore.saveAssessment(
      session['session_id'] as String,
      const SessionAssessment(
        actualTimeMinutes: 20,
        difficultyScore: 2,
        difficultyComment: '',
        issues: [],
        changesMade: [],
        overall: 4,
        taste: [],
        comment: '前回の感想',
        nextTimeIntent: [],
      ),
    );
    final controller = RecipeLibraryController(
      _MemoryRecipeDocumentStore([recipe.raw]),
      _MemoryRecipeTagStore(),
      validator,
      () async => null,
      cookingStore: cookingStore,
    );
    await controller.load();
    final share = _FakeFeedbackSharePlatform();
    await tester.pumpWidget(
      MaterialApp(
        home: FeedbackScreen(
          recipeId: recipe.id,
          controller: controller,
          sharePlatform: share,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('feedback_goal')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byKey(const Key('feedback_goal')), '塩味を調整する');
    await tester.scrollUntilVisible(
      find.byKey(const Key('share_feedback')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('share_feedback')));
    await tester.pumpAndSettle();
    expect(find.text('Feedbackを共有しますか？'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm_share_feedback')));
    await tester.pumpAndSettle();
    await _pumpUntilFeedbackShared(tester, share.shared);
    await tester.pump();
    expect(share.sources, hasLength(1));
    final feedback = jsonDecode(share.sources.single) as Map<String, dynamic>;
    expect(feedback['type'], 'recipe_feedback');
    expect(
      (feedback['cook_session'] as Map)['cooking_context']['target_servings'],
      3,
    );
    expect((feedback['revision_request'] as Map)['next_revision'], 2);
    final saved =
        ((await cookingStore.read())['sessions'] as List).single as Map;
    expect((saved['assessment'] as Map)['actual_time_minutes'], 20);
  });

  testWidgets('records the first assessment for a completed cook', (
    tester,
  ) async {
    final validator = RecipeValidator.fromSchemaString(schemaSource);
    final recipe = validator.validateSource(recipeSource);
    final cookingStore = CookingStore(null, validator);
    await cookingStore.startCooking(recipe, recipe.contextFor(2), 'step-onion');
    await cookingStore.complete(recipe.id, recipe.revision);
    final controller = RecipeLibraryController(
      _MemoryRecipeDocumentStore([recipe.raw]),
      _MemoryRecipeTagStore(),
      validator,
      () async => null,
      cookingStore: cookingStore,
    );
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        home: FeedbackScreen(recipeId: recipe.id, controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('feedback_difficulty')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('feedback_difficulty')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('feedback_overall')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('feedback_overall')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('4').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('save_assessment')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.byKey(const Key('save_assessment')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save_assessment')));
    await tester.pumpAndSettle();
    final session =
        ((await cookingStore.read())['sessions'] as List).single as Map;
    final assessment = session['assessment'] as Map;
    expect((assessment['difficulty'] as Map)['score'], 2);
    expect((assessment['evaluation'] as Map)['overall'], 4);
    expect(assessment['actual_time_minutes'], greaterThanOrEqualTo(1));
  });
  testWidgets('settings, information and archive fit narrow enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = RecipeLibraryController(
      _MemoryRecipeDocumentStore([
        jsonDecode(recipeSource) as Map<String, dynamic>,
      ]),
      _MemoryRecipeTagStore(),
      RecipeValidator.fromSchemaString(schemaSource),
      () async => null,
    );
    await controller.load();
    await controller.setArchived(controller.recipes.single.id, true);
    await tester.pumpWidget(
      MaterialApp(
        theme: RecipeTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: HomeScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open_settings')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const Key('app_information_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('app_information_button')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open_recipe_archive')));
    await tester.pumpAndSettle();
    expect(find.text('豚の生姜焼き'), findsOneWidget);
    expect(find.byTooltip('アーカイブの操作').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  for (final width in [320.0, 412.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'remaining recipe screens scroll without overflow $width/$scale',
        (tester) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final validator = RecipeValidator.fromSchemaString(schemaSource);
          final longDocument = jsonDecode(recipeSource) as Map<String, dynamic>;
          longDocument['recipe']['title'] = '野菜をたっぷり使った、家族みんなで楽しむ豚の生姜焼き';
          longDocument['recipe']['ingredients'][0]['name'] =
              '国産の豚こま切れ肉（食べやすい大きさに切ったもの）';
          final recipe = validator.validateSource(jsonEncode(longDocument));
          final cookingStore = CookingStore(null, validator);
          await cookingStore.startCooking(
            recipe,
            recipe.contextFor(2),
            'step-onion',
          );
          await cookingStore.complete(recipe.id, recipe.revision);
          await cookingStore.markHelpSeen();
          final controller = RecipeLibraryController(
            _MemoryRecipeDocumentStore([recipe.raw]),
            _MemoryRecipeTagStore(),
            validator,
            () async => null,
            cookingStore: cookingStore,
          );
          await controller.load();
          for (final screen in [
            RecipeDetailScreen(recipe: recipe, controller: controller),
            RecipeVersionHistoryScreen(
              recipeId: recipe.id,
              controller: controller,
            ),
            FeedbackScreen(recipeId: recipe.id, controller: controller),
            CookingScreen(
              recipe: recipe,
              store: cookingStore,
              initialIndex: 0,
              cookingContext: recipe.contextFor(2),
            ),
          ]) {
            if (screen is CookingScreen) {
              await cookingStore.startCooking(
                recipe,
                recipe.contextFor(2),
                recipe.steps.first['id'] as String,
              );
            }
            await tester.pumpWidget(
              MaterialApp(
                key: UniqueKey(),
                theme: RecipeTheme.light,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: screen,
              ),
            );
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: screen.runtimeType.toString(),
            );
            final scroller = find.byType(Scrollable).first;
            for (var sweep = 0; sweep < 60; sweep++) {
              final position = tester.state<ScrollableState>(scroller).position;
              if (position.pixels >= position.maxScrollExtent) break;
              await tester.drag(scroller, const Offset(0, -400));
              await tester.pumpAndSettle();
              expect(
                tester.takeException(),
                isNull,
                reason: '${screen.runtimeType} while scrolling',
              );
            }
            if (screen is CookingScreen) {
              expect(
                find.byKey(const Key('next_step_button')).hitTestable(),
                findsOneWidget,
              );
              await tester.tap(find.byKey(const Key('next_step_button')));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              await tester.tap(find.byKey(const Key('next_step_button')));
              await tester.pumpAndSettle();
              expect(
                find.byKey(const Key('complete_cooking')).hitTestable(),
                findsOneWidget,
              );
              expect(find.byKey(const Key('next_step_button')), findsNothing);
              expect(tester.takeException(), isNull);
            }
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
          }
          expect(controller.revisionsFor(recipe.id).single.raw, recipe.raw);
          controller.dispose();
        },
      );
    }
  }
}

class _MemoryRecipeDocumentStore implements RecipeDocumentStore {
  _MemoryRecipeDocumentStore([List<Map<String, dynamic>>? initial])
    : documents = [...?initial];

  final List<Map<String, dynamic>> documents;

  @override
  Future<List<Map<String, dynamic>>> loadDocuments() async => [...documents];

  @override
  Future<StoreRecipeResult> saveDocument(Map<String, dynamic> document) async {
    documents.add(document);
    return StoreRecipeResult.added;
  }
}

class _QuickSwitchVersionStore extends MemoryRecipeVersionStateStore {
  _QuickSwitchVersionStore(super.initial);

  int writes = 0;
  bool fail = false;

  @override
  Future<void> saveActiveRevision(String recipeId, int revision) async {
    writes++;
    if (fail) {
      throw const RecipeVersionStateStorageException('切替の保存に失敗しました。');
    }
    await super.saveActiveRevision(recipeId, revision);
  }
}

class _FakeRecipeSharePlatform implements RecipeSharePlatform {
  final _sources = <String>[];
  void Function()? _incoming;

  void add(String source) {
    _sources.add(source);
    _incoming?.call();
  }

  @override
  void setIncomingHandler(void Function() handler) => _incoming = handler;

  @override
  Future<String?> takeNext() async =>
      _sources.isEmpty ? null : _sources.removeAt(0);

  @override
  void dispose() => _incoming = null;
}

// Asset I/O uses real events while widget callbacks use the fake clock. Pump
// both until the observable share occurs, instead of awaiting a fake-zone
// Completer inside runAsync (which can leave its callbacks unprocessed).
Future<void> _pumpUntilFeedbackShared(
  WidgetTester tester,
  Completer<void> signal,
) async {
  for (var attempt = 0; attempt < 100 && !signal.isCompleted; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  expect(signal.isCompleted, isTrue);
}

class _FakeFeedbackSharePlatform implements FeedbackSharePlatform {
  final sources = <String>[];
  final shared = Completer<void>();

  @override
  Future<void> shareJson(String source) async {
    sources.add(source);
    if (!shared.isCompleted) shared.complete();
  }
}

class _MemoryRecipeTagStore implements RecipeTagStore {
  final Map<String, List<String>> tagsByRecipeId = {};

  @override
  Future<Map<String, List<String>>> loadTags() async => {
    for (final entry in tagsByRecipeId.entries) entry.key: [...entry.value],
  };

  @override
  Future<void> saveTags(String recipeId, List<String> tags) async {
    if (tags.isEmpty) {
      tagsByRecipeId.remove(recipeId);
    } else {
      tagsByRecipeId[recipeId] = [...tags];
    }
  }
}

class _WidgetRecipeInboxPlatform implements RecipeInboxPlatform {
  _WidgetRecipeInboxPlatform(this.file);

  final RecipeInboxFile file;

  @override
  Future<List<RecipeInboxFile>> readFiles(RecipeInboxFolder folder) async => [
    file,
  ];

  @override
  Future<void> releaseFolder(RecipeInboxFolder folder) async {}

  @override
  Future<RecipeInboxFolder?> selectFolder() async => const RecipeInboxFolder(
    treeUri: 'content://provider/tree/inbox',
    displayName: 'Inbox',
  );
}

class _BlockingWidgetRecipeInboxPlatform implements RecipeInboxPlatform {
  _BlockingWidgetRecipeInboxPlatform(this.pendingFiles);

  final Future<List<RecipeInboxFile>> pendingFiles;

  @override
  Future<List<RecipeInboxFile>> readFiles(RecipeInboxFolder folder) =>
      pendingFiles;

  @override
  Future<void> releaseFolder(RecipeInboxFolder folder) async {}

  @override
  Future<RecipeInboxFolder?> selectFolder() async => null;
}

class _WidgetRecipeInboxStateStore implements RecipeInboxStateStore {
  _WidgetRecipeInboxStateStore([this.state = RecipeInboxState.empty]);

  RecipeInboxState state;

  @override
  Future<void> addReceipts(Iterable<RecipeInboxReceipt> receipts) async {
    state = RecipeInboxState(
      folder: state.folder,
      receipts: [...state.receipts, ...receipts],
    );
  }

  @override
  Future<RecipeInboxState> load() async => state;

  @override
  Future<void> saveFolder(RecipeInboxFolder folder) async {
    state = RecipeInboxState(folder: folder, receipts: state.receipts);
  }
}
