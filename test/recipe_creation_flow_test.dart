import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:siwc_client/siwc_contract.dart';
import 'package:recipe_cooking_navigator/application/recipe_ai_client.dart';
import 'package:recipe_cooking_navigator/application/recipe_ai_session.dart';
import 'package:recipe_cooking_navigator/application/recipe_creation_controller.dart';
import 'package:recipe_cooking_navigator/application/recipe_library_controller.dart';
import 'package:recipe_cooking_navigator/data/recipe_creation_store.dart';
import 'package:recipe_cooking_navigator/data/recipe_document_store.dart';
import 'package:recipe_cooking_navigator/data/recipe_tag_store.dart';
import 'package:recipe_cooking_navigator/domain/ai_recipe_prompt.dart';
import 'package:recipe_cooking_navigator/domain/ai_recipe_request.dart';
import 'package:recipe_cooking_navigator/domain/recipe_validator.dart';
import 'package:recipe_cooking_navigator/domain/feedback_validator.dart';
import 'package:recipe_cooking_navigator/platform/ai_request_platform.dart';
import 'package:recipe_cooking_navigator/ui/ai_recipe_request_screen.dart';
import 'package:recipe_cooking_navigator/ui/home_screen.dart';
import 'package:recipe_cooking_navigator/ui/recipe_ai_scope.dart';
import 'package:recipe_cooking_navigator/ui/recipe_import_screen.dart';
import 'package:recipe_cooking_navigator/ui/recipe_theme.dart';
import 'package:recipe_cooking_navigator/ui/recipe_ai_settings_screen.dart';

class _Client implements RecipeAiClient {
  bool enabled = true;
  String answer = '';
  String? sentInput;
  Object? failure;
  int calls = 0;
  Completer<String>? pending;
  @override
  bool get connected => enabled;
  @override
  bool get canInfer => enabled;
  @override
  String? get activeAccount => 'test';
  @override
  List<({String id, String label})> get accounts => [
    (id: 'test', label: 'テスト'),
  ];
  @override
  Future<void> initialize() async {}
  @override
  Future<void> signIn({bool newAccount = false}) async {
    enabled = true;
  }

  @override
  Future<void> selectAccount(String id) async {}
  @override
  Future<List<({String slug, String name})>> listModels() async => [
    (slug: 'a', name: 'A'),
    (slug: 'b', name: 'B'),
  ];
  @override
  Future<String?> dictate() async => null;
  @override
  Future<String> infer(
    String model,
    String input, {
    required String instructions,
  }) async {
    calls++;
    sentInput = input;
    if (failure != null) throw failure!;
    return pending?.future ?? answer;
  }

  @override
  Future<bool> disconnect() async {
    enabled = false;
    return true;
  }

  @override
  Future<void> openUsage() async {}
  @override
  void cancel() {}
}

class _Store implements RecipeDocumentStore {
  final docs = <Map<String, dynamic>>[];
  bool fail = false, partial = false;
  int calls = 0;
  @override
  Future<List<Map<String, dynamic>>> loadDocuments() async => docs;
  @override
  Future<StoreRecipeResult> saveDocument(Map<String, dynamic> document) async {
    calls++;
    if (fail && !partial) {
      fail = false;
      throw const RecipeStorageException('fail');
    }
    final exists = docs.any((d) => jsonEncode(d) == jsonEncode(document));
    if (!exists) docs.add(document);
    if (fail) {
      fail = false;
      throw const RecipeStorageException('partial');
    }
    return exists ? StoreRecipeResult.alreadyExists : StoreRecipeResult.added;
  }
}

class _Tags implements RecipeTagStore {
  @override
  Future<Map<String, List<String>>> loadTags() async => {};
  @override
  Future<void> saveTags(String id, List<String> tags) async {}
}

class _FailingRecordStore extends RecipeCreationStore {
  @override
  Future<void> update(String key, Object? value) async =>
      throw const FileSystemException('write failed');
}

class _External implements AiRequestPlatform {
  @override
  Future<void> share(String request) async {}
  @override
  Future<void> openChatGpt() async {}
}

void main() {
  late String source, schema, feedbackSchema;
  late Map<String, dynamic> feedback;
  late _Client client;
  late _Store store;
  late RecipeLibraryController library;
  late RecipeAiSession session;
  late RecipeCreationController flow;
  final request = AiRecipeRequest.generate(
    ingredients: 'なす',
    servings: 2,
    timeMinutes: 30,
    utensils: '',
    taste: '',
  );
  const prompt = AiRecipePrompt(
    recipeSchema: '',
    generateWorkflow: '',
    improveWorkflow: '',
    integration: '',
    example: '',
  );
  setUpAll(() async {
    source = await File('examples/recipe-example.json').readAsString();
    schema = await File('schemas/recipe-v2.schema.json').readAsString();
    feedbackSchema = await File('schemas/feedback-v2.schema.json')
        .readAsString();
    feedback = jsonDecode(
      await File('examples/feedback-example.json').readAsString(),
    ) as Map<String, dynamic>;
  });
  setUp(() async {
    client = _Client()..answer = source;
    store = _Store();
    library = RecipeLibraryController(
      store,
      _Tags(),
      RecipeValidator.fromSchemaString(schema),
      () async => source,
    );
    await library.load();
    session = RecipeAiSession(client, RecipeCreationStore());
    await session.initialize();
    flow = RecipeCreationController(session, library);
  });
  tearDown(() {
    flow.dispose();
    session.dispose();
  });

  test('cancelled attempt cannot overwrite a newer candidate and double generation sends once', () async {
    client.pending = Completer<String>();
    final old = flow.generate(request, request.directText, () async => prompt);
    await Future<void>.delayed(Duration.zero);
    await flow.generate(request, request.directText, () async => prompt);
    expect(client.calls, 1);
    final pending = client.pending!;
    flow.cancel();
    client.pending = null;
    await flow.generate(request, 'new conditions', () async => prompt);
    final candidate = flow.preview;
    pending.complete('invalid old result');
    await old;
    expect(flow.preview, same(candidate));
    expect(flow.candidateConditions, 'new conditions');
    expect(flow.stage, RecipeCreationStage.preview);
    expect(store.docs, isEmpty);
  });
  for (final partial in [false, true]) {
    test(
      'save retry retains result without inference, partial=$partial',
      () async {
        await flow.generate(request, request.directText, () async => prompt);
        store
          ..fail = true
          ..partial = partial;
        final first = await flow.save();
        expect(first!.status, RecipeImportStatus.failed);
        expect(flow.preview, isNotNull);
        final retry = flow.save();
        expect(await flow.save(), isNull);
        expect(
          (await retry)!.status,
          partial
              ? RecipeImportStatus.alreadyExists
              : RecipeImportStatus.imported,
        );
        expect(client.calls, 1);
        expect(store.docs, hasLength(1));
        expect(
          library.revisionFor(flow.preview!.recipeId, flow.preview!.revision),
          isNotNull,
        );
      },
    );
  }
  test(
    'failed regeneration and foreign import preserve the candidate',
    () async {
      await flow.generate(request, request.directText, () async => prompt);
      final candidate = flow.preview;
      flow.edit();
      client.answer = 'broken';
      await flow.generate(request, 'changed', () async => prompt);
      expect(flow.preview, same(candidate));
      expect((await library.prepareImportSource(source)).preview, isNull);
      library.cancelPreparedImport(candidate!);
      final foreign = (await library.prepareImportSource(source)).preview!;
      expect((await flow.save())!.status, RecipeImportStatus.failed);
      expect(store.docs, isEmpty);
      library.cancelPreparedImport(foreign);
    },
  );
  test('draft and model survive reconstruction and successful clear', () async {
    final directory = await Directory.systemTemp.createTemp(
      'recipe-draft-test',
    );
    try {
      final file = File('${directory.path}/draft.json');
      final first = RecipeAiSession(client, RecipeCreationStore(file));
      await first.initialize();
      await first.selectModel('b');
      await first.saveDraft({'ingredients': 'なす', 'hasResult': true});
      first.dispose();
      final restored = RecipeAiSession(client, RecipeCreationStore(file));
      await restored.initialize();
      expect(restored.model, 'b');
      expect(restored.draft!['ingredients'], 'なす');
      expect(restored.interruptedResult, isTrue);
      expect(client.calls, 0);
      await restored.saveDraft(null);
      expect(jsonDecode(await file.readAsString())['draft'], isNull);
      restored.dispose();
    } finally {
      await directory.delete(recursive: true);
    }
  });
  test(
    'successful request evidence survives reload without changing Recipe JSON',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'recipe-conditions-test',
      );
      try {
        final file = File('${directory.path}/records.json');
        flow.dispose();
        library = RecipeLibraryController(
          store,
          _Tags(),
          RecipeValidator.fromSchemaString(schema),
          () async => null,
          creationRecordStore: RecipeCreationStore(file),
        );
        await library.load();
        flow = RecipeCreationController(session, library);
        await flow.generate(request, request.directText, () async => prompt);
        final candidate = flow.preview!;
        await flow.save();
        expect(store.docs.single, jsonDecode(source));
        final description = library.creationConditionsFor(
          candidate.recipeId,
          candidate.revision,
        )!;
        expect(description, contains('使用モデル: a'));
        expect(description, contains(request.directText));
        final restored = RecipeLibraryController(
          store,
          _Tags(),
          RecipeValidator.fromSchemaString(schema),
          () async => null,
          creationRecordStore: RecipeCreationStore(file),
        );
        await restored.load();
        expect(
          restored.creationConditionsFor(
            candidate.recipeId,
            candidate.revision,
          ),
          description,
        );
        await restored.recordCreationConditions(
          candidate.recipeId,
          candidate.revision,
          'different later request',
        );
        expect(
          restored.creationConditionsFor(
            candidate.recipeId,
            candidate.revision,
          ),
          description,
        );
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
  test(
    'failed regeneration retains the original request and model evidence',
    () async {
      await flow.generate(request, 'original condition', () async => prompt);
      await session.selectModel('b');
      client.answer = 'broken';
      await flow.generate(request, 'new condition', () async => prompt);
      expect(flow.candidateConditions, 'original condition');
      expect(flow.candidateModel, 'a');
      expect(flow.candidateRequest, same(request));
    },
  );
  test(
    'condition write failure reports warning but keeps the saved recipe',
    () async {
      flow.dispose();
      library = RecipeLibraryController(
        store,
        _Tags(),
        RecipeValidator.fromSchemaString(schema),
        () async => null,
        creationRecordStore: _FailingRecordStore(),
      );
      await library.load();
      flow = RecipeCreationController(session, library);
      await flow.generate(request, request.directText, () async => prompt);
      expect((await flow.save())!.status, RecipeImportStatus.imported);
      expect(flow.stage, RecipeCreationStage.saved);
      expect(flow.conditionsSaveWarning, contains('作成条件の記録を保存できません'));
      expect(store.docs, hasLength(1));
    },
  );
  testWidgets(
    'home to creation to save takes three main taps and opens exact recipe',
    (tester) async {
      library = RecipeLibraryController(
        store,
        _Tags(),
        RecipeValidator.fromSchemaString(schema),
        () async => source,
      );
      await library.load();
      await tester.pumpWidget(
        RecipeAiScope(
          session: session,
          child: MaterialApp(home: HomeScreen(controller: library)),
        ),
      );
      await tester.tap(find.byKey(const Key('create_chatgpt_recipe')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('ai_食材')), 'なす');
      await tester.tap(find.byKey(const Key('connected_ai_send')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('connected_ai_text')), findsNothing);
      expect(find.byKey(const Key('connected_ai_send')), findsNothing);
      expect(find.text('材料と分量'), findsOneWidget);
      expect(store.docs, isEmpty);
      await tester.tap(find.byKey(const Key('connected_ai_save')));
      await tester.pumpAndSettle();
      expect(find.text('レシピ詳細'), findsOneWidget);
      expect(store.docs, hasLength(1));
      expect(session.draft, isNull);
    },
  );
  testWidgets('stored duplicate is labelled saved and back needs no discard', (
    tester,
  ) async {
    store.docs.add(jsonDecode(source) as Map<String, dynamic>);
    library = RecipeLibraryController(
      store,
      _Tags(),
      RecipeValidator.fromSchemaString(schema),
      () async => source,
    );
    await library.load();
    final prepared = await library.prepareImportSource(source);
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(controller: library),
        initialRoute: '/preview',
        routes: {
          '/preview': (_) =>
              RecipeImportScreen(library: library, preview: prepared.preview!),
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('このレシピは保存済みです'), findsOneWidget);
    expect(find.text('まだ保存されていません'), findsNothing);
    expect(find.text('保存済みのレシピを開く'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('保存せずに戻りますか？'), findsNothing);
    expect(find.byKey(const Key('create_chatgpt_recipe')), findsOneWidget);
    expect(store.calls, 0);
    expect(store.docs, hasLength(1));
  });

  testWidgets(
    'settings round trip preserves conditions and never sends automatically',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AiRecipeRequestScreen(library: library, session: session),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('ai_食材')), 'なす');
      await tester.tap(find.text('変更'));
      await tester.pumpAndSettle();
      expect(find.text('ChatGPT連携'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('ai_食材')))
            .controller!
            .text,
        'なす',
      );
      expect(client.calls, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final useFuture in [false, true]) {
    testWidgets(
      'improvement saves the displayed revision; explicit future selection=$useFuture',
      (tester) async {
        final base = feedback['recipe_snapshot'] as Map<String, dynamic>;
        store.docs.add(base);
        library = RecipeLibraryController(
          store,
          _Tags(),
          RecipeValidator.fromSchemaString(schema),
          () async => null,
        );
        await library.load();
        final next = jsonDecode(jsonEncode(base)) as Map<String, dynamic>;
        final recipe = next['recipe'] as Map;
        recipe['revision'] =
            (feedback['revision_request'] as Map)['next_revision'];
        recipe['parent_revision'] = (base['recipe'] as Map)['revision'];
        recipe['title'] = '改善したレシピ';
        client.answer = jsonEncode(next);
        final improvement = AiRecipeRequest.improve(
          feedback: feedback,
          validator: FeedbackValidator.fromSchemaStrings(
            feedbackSchemaSource: feedbackSchema,
            recipeSchemaSource: schema,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: AiRecipeRequestScreen(
              improvementRequest: improvement,
              library: library,
              session: session,
              prompt: prompt,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final goal = (feedback['revision_request'] as Map)['goal'];
        expect(find.text(goal as String), findsOneWidget);
        expect(find.text('評価から引き継いだ改善の希望'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byKey(const Key('connected_ai_text')),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.enterText(
          find.byKey(const Key('connected_ai_text')),
          '洗い物を少なく',
        );
        await tester.tap(find.byKey(const Key('connected_ai_send')));
        await tester.pumpAndSettle();
        final sent = jsonDecode(client.sentInput!) as Map;
        expect(
          (sent['selected_feedback']['revision_request'] as Map)['goal'],
          goal,
        );
        expect(sent['selected_feedback'], feedback);
        expect(sent['confirmed_request'], contains('洗い物を少なく'));
        expect(find.text('改善前後の比較'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byKey(const Key('candidate_conditions')),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.byKey(const Key('candidate_conditions')));
        await tester.pumpAndSettle();
        expect(find.text(goal), findsOneWidget);
        expect(find.textContaining('使用モデル: a'), findsOneWidget);
        expect(find.textContaining('追加の希望: 洗い物を少なく'), findsOneWidget);
        await tester.tap(find.byKey(const Key('previous_recipe_revision')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('connected_ai_preview')), findsOneWidget);
        expect(find.text('このバージョンを開く'), findsOneWidget);
        expect(store.docs, hasLength(1));
        expect(
          library.activeRecipeFor(recipe['id'] as String)!.revision,
          recipe['parent_revision'],
        );
        await tester.tap(find.byKey(const Key('next_recipe_revision')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            Key(useFuture ? 'use_preview_recipe' : 'connected_ai_save'),
          ),
        );
        if (useFuture) {
          await tester.pumpAndSettle();
          expect(store.docs, hasLength(1));
          await tester.tap(find.byKey(const Key('confirm_future_recipe')));
        }
        await tester.pumpAndSettle();
        expect(find.text('改善したレシピ'), findsOneWidget);
        expect(
          find.text('${useFuture ? '使用中' : '表示中'}のバージョン ${recipe['revision']}'),
          findsOneWidget,
        );
        expect(
          library.activeRecipeFor(recipe['id'] as String)!.revision,
          useFuture ? recipe['revision'] : recipe['parent_revision'],
        );
        expect(store.docs, hasLength(2));
        expect(
          library.creationConditionsFor(
            recipe['id'] as String,
            recipe['revision'] as int,
          ),
          contains(goal),
        );
        expect(
          library.creationConditionsFor(
            recipe['id'] as String,
            recipe['revision'] as int,
          ),
          contains('洗い物を少なく'),
        );
      },
    );
  }

  test(
    'receive limit and timeout failures preserve the request without saving',
    () async {
      for (final kind in [
        SiwcFailureKind.responseTooLarge,
        SiwcFailureKind.timeout,
      ]) {
        client.failure = SiwcFailure('safe diagnosis', kind: kind);
        await session.initialize();
        await flow.generate(request, request.directText, () async => prompt);
        expect(flow.stage, RecipeCreationStage.editing);
        expect(flow.failureKind, kind);
        expect(
          flow.message,
          contains(kind == SiwcFailureKind.timeout ? '時間切れ' : '受信量が上限'),
        );
        expect(flow.diagnostic, 'safe diagnosis');
        expect(store.docs, isEmpty);
        expect(store.calls, 0);
      }
    },
  );

  testWidgets(
    'external improvement rejects a different identity and accepts the matching answer without inference',
    (tester) async {
      final base = feedback['recipe_snapshot'] as Map<String, dynamic>;
      store.docs.add(base);
      library = RecipeLibraryController(
        store,
        _Tags(),
        RecipeValidator.fromSchemaString(schema),
        () async => null,
      );
      await library.load();
      final next = jsonDecode(jsonEncode(base)) as Map<String, dynamic>;
      final recipe = next['recipe'] as Map;
      final id = recipe['id'];
      recipe['revision'] =
          (feedback['revision_request'] as Map)['next_revision'];
      recipe['parent_revision'] = (base['recipe'] as Map)['revision'];
      recipe['id'] = 'different-recipe';
      final improvement = AiRecipeRequest.improve(
        feedback: feedback,
        validator: FeedbackValidator.fromSchemaStrings(
          feedbackSchemaSource: feedbackSchema,
          recipeSchemaSource: schema,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AiRecipeRequestScreen(
            improvementRequest: improvement,
            library: library,
            session: session,
            platform: _External(),
            publicReady: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scrollable = find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('別の方法で作る'),
        200,
        scrollable: scrollable,
      );
      await tester.tap(find.text('別の方法で作る'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('share_ai_request')));
      await tester.tap(find.byKey(const Key('share_ai_request')));
      await tester.pumpAndSettle();
      for (final valid in [false, true]) {
        if (valid) recipe['id'] = id;
        await tester.scrollUntilVisible(
          find.text('回答を貼り付ける'),
          200,
          scrollable: scrollable,
        );
        await tester.tap(find.text('回答を貼り付ける'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('paste_recipe_source')),
          jsonEncode(next),
        );
        await tester.tap(find.byKey(const Key('preview_pasted_recipe')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('connected_ai_save')),
          valid ? findsOneWidget : findsNothing,
        );
      }
      expect(client.calls, 0);
      expect(store.docs, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final width in [320.0, 360.0, 412.0]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets(
        'creation, busy, preview, empty home fit width=$width scale=$scale',
        (tester) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          Widget host(Widget child) => MaterialApp(
            theme: RecipeTheme.light,
            builder: (context, body) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: body!,
            ),
            home: child,
          );
          await tester.pumpWidget(
            host(
              AiRecipeRequestScreen(
                library: library,
                session: session,
                prompt: prompt,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.scrollUntilVisible(
            find.byKey(const Key('ai_食材')),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.enterText(find.byKey(const Key('ai_食材')), 'なす');
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(
            tester.getSize(find.byKey(const Key('connected_ai_send'))).height,
            greaterThanOrEqualTo(48),
          );
          tester.view.resetViewInsets();
          client.pending = Completer<String>();
          await tester.tap(find.byKey(const Key('connected_ai_send')));
          await tester.pump();
          expect(tester.takeException(), isNull);
          client.pending!.complete(source);
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('connected_ai_save')), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(
            host(RecipeAiSettingsScreen(session: session)),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.byKey(const ValueKey('model-a')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('model-a')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('B').last);
          await tester.pumpAndSettle();
          expect(session.model, 'b');
          expect(client.calls, 1);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(host(HomeScreen(controller: library)));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
