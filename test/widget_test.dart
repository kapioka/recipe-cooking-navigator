import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_cooking_navigator/application/recipe_library_controller.dart';
import 'package:recipe_cooking_navigator/data/cooking_store.dart';
import 'package:recipe_cooking_navigator/data/recipe_document_store.dart';
import 'package:recipe_cooking_navigator/data/recipe_tag_store.dart';
import 'package:recipe_cooking_navigator/domain/recipe_validator.dart';
import 'package:recipe_cooking_navigator/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String schemaSource;
  late String recipeSource;
  late List<MethodCall> cookingCalls;

  setUpAll(() async {
    schemaSource = await File('schemas/recipe-v1.schema.json').readAsString();
    recipeSource = await File('examples/recipe-example.json').readAsString();
  });

  setUp(() {
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
    await tester.tap(find.byKey(const Key('import_recipe_button')));
    await tester.pumpAndSettle();

    expect(find.text('豚の生姜焼き'), findsOneWidget);
    expect(find.textContaining('2人分'), findsOneWidget);

    await tester.tap(find.text('豚の生姜焼き'));
    await tester.pumpAndSettle();

    expect(find.text('レシピ詳細'), findsOneWidget);
    expect(find.text('材料'), findsOneWidget);
    expect(find.text('豚こま切れ肉'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('全体工程'), 300);
    expect(find.text('全体工程'), findsOneWidget);
  });

  testWidgets('shows attribution and food safety notice', (tester) async {
    final controller = RecipeLibraryController(
      _MemoryRecipeDocumentStore(),
      _MemoryRecipeTagStore(),
      RecipeValidator.fromSchemaString(schemaSource),
      () async => null,
    );
    await controller.load();

    await tester.pumpWidget(RecipeCookingNavigatorApp(controller: controller));
    await tester.tap(find.byKey(const Key('app_information_button')));
    await tester.pumpAndSettle();

    expect(find.text('このアプリについて'), findsOneWidget);
    expect(find.text('安全に関する注意'), findsOneWidget);
    expect(find.textContaining('アレルギー'), findsOneWidget);
    expect(find.textContaining('Apache License 2.0'), findsOneWidget);
    expect(find.textContaining('Copyright 2026 kapioka'), findsOneWidget);
    expect(
      find.byKey(const Key('open_source_licenses_button')),
      findsOneWidget,
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
    await tester.tap(find.byKey(const Key('import_recipe_button')));
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
    expect(find.text('時短'), findsOneWidget);

    await tester.tap(find.byTooltip('戻る'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('recipe_search_field')), '時');
    await tester.pump();
    expect(find.text('豚の生姜焼き'), findsOneWidget);
    expect(find.text('タグ'), findsOneWidget);
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
    await tester.tap(find.byKey(const Key('import_recipe_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('豚の生姜焼き'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('start_cooking')));
    await tester.pumpAndSettle();
    expect(find.text('画面操作の説明'), findsOneWidget);
    await tester.tap(find.text('調理画面へ戻る'));
    await tester.pumpAndSettle();
    expect(find.text('玉ねぎを炒める'), findsOneWidget);

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

    await tester.tap(find.byKey(const Key('resume_cooking')));
    await tester.pumpAndSettle();
    expect(find.text('生姜だれを煮絡める'), findsOneWidget);
    expect(find.textContaining('調理画面の操作'), findsNothing);
    await tester.tap(find.byTooltip('その他の操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('調理を完了'));
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
}

class _MemoryRecipeDocumentStore implements RecipeDocumentStore {
  final List<Map<String, dynamic>> documents = [];

  @override
  Future<List<Map<String, dynamic>>> loadDocuments() async => [...documents];

  @override
  Future<StoreRecipeResult> saveDocument(Map<String, dynamic> document) async {
    documents.add(document);
    return StoreRecipeResult.added;
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
