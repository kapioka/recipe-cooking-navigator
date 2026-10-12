import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_cooking_navigator/application/ai_recipe_import.dart';
import 'package:recipe_cooking_navigator/application/recipe_ai_client.dart';
import 'package:recipe_cooking_navigator/application/recipe_library_controller.dart';
import 'package:recipe_cooking_navigator/data/recipe_document_store.dart';
import 'package:recipe_cooking_navigator/data/recipe_tag_store.dart';
import 'package:recipe_cooking_navigator/data/recipe_version_state_store.dart';
import 'package:recipe_cooking_navigator/domain/ai_recipe_prompt.dart';
import 'package:recipe_cooking_navigator/domain/ai_recipe_request.dart';
import 'package:recipe_cooking_navigator/domain/ai_recipe_response_diagnostic.dart';
import 'package:recipe_cooking_navigator/domain/feedback_validator.dart';
import 'package:recipe_cooking_navigator/domain/recipe_validator.dart';
import 'package:recipe_cooking_navigator/ui/connected_recipe_screen.dart';

class _Store implements RecipeDocumentStore {
  final documents = <Map<String, dynamic>>[];
  @override
  Future<List<Map<String, dynamic>>> loadDocuments() async => documents;
  @override
  Future<StoreRecipeResult> saveDocument(Map<String, dynamic> document) async {
    final recipe = document['recipe'] as Map;
    for (final saved in documents) {
      final old = saved['recipe'] as Map;
      if (old['id'] == recipe['id'] && old['revision'] == recipe['revision']) {
        return jsonEncode(saved) == jsonEncode(document)
            ? StoreRecipeResult.alreadyExists
            : StoreRecipeResult.conflictingRevision;
      }
    }
    documents.add(document);
    return StoreRecipeResult.added;
  }
}

class _Tags implements RecipeTagStore {
  @override
  Future<Map<String, List<String>>> loadTags() async => {};
  @override
  Future<void> saveTags(String recipeId, List<String> tags) async {}
}

class _FailingVersions extends MemoryRecipeVersionStateStore {
  @override
  Future<void> saveActiveRevision(String recipeId, int revision) async {
    throw const RecipeVersionStateStorageException('検証用の保存失敗');
  }
}

class _Client implements RecipeAiClient {
  String response = '普通の回答です';
  Completer<String>? pending;
  final prompts = <String>[];
  final instructionsSent = <String>[];
  int cancels = 0;
  @override
  bool get connected => true;
  @override
  bool get canInfer => true;
  @override
  String? get activeAccount => 'test';
  @override
  List<({String id, String label})> get accounts => [
    (id: 'test', label: '検証用'),
  ];
  @override
  Future<void> initialize() async {}
  @override
  Future<void> signIn({bool newAccount = false}) async {}
  @override
  Future<void> selectAccount(String id) async {}
  @override
  Future<List<({String slug, String name})>> listModels() async => [
    (slug: 'detected', name: '検出モデル'),
  ];
  @override
  Future<String?> dictate() async => '卵で一人分。安全に加熱してください。';
  @override
  Future<String> infer(
    String model,
    String prompt, {
    required String instructions,
  }) async {
    prompts.add(prompt);
    instructionsSent.add(instructions);
    return pending?.future ?? response;
  }

  @override
  Future<bool> disconnect() async => true;
  @override
  Future<void> openUsage() async {}
  @override
  void cancel() {
    cancels++;
  }
}

void main() {
  Future<void> visible(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        250,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
    } else {
      await tester.ensureVisible(finder);
    }
    await tester.pumpAndSettle();
  }

  late String schema, feedbackSchema, recipeSource;
  late Map<String, dynamic> feedback;
  late AiRecipePrompt prompt;
  late _Store store;
  late RecipeLibraryController library;
  final request = AiRecipeRequest.generate(
    ingredients: '卵',
    servings: 1,
    utensils: 'フライパン',
    taste: '',
    timeMinutes: 10,
  );
  setUpAll(() async {
    schema = await File('schemas/recipe-v2.schema.json').readAsString();
    feedbackSchema = await File('schemas/feedback-v2.schema.json')
        .readAsString();
    recipeSource = await File('examples/recipe-example.json').readAsString();
    feedback = jsonDecode(
      await File('examples/feedback-example.json').readAsString(),
    ) as Map<String, dynamic>;
    prompt = AiRecipePrompt(
      recipeSchema: schema,
      feedbackSchema: feedbackSchema,
      generateWorkflow: await File('ai/workflows/generate.md').readAsString(),
      improveWorkflow: await File('ai/workflows/improve.md').readAsString(),
      integration: await File('docs/chatgpt-integration.md').readAsString(),
      example: await File('examples/recipe-v2-split-example.json')
          .readAsString(),
    );
  });
  setUp(() async {
    store = _Store();
    library = RecipeLibraryController(
      store,
      _Tags(),
      RecipeValidator.fromSchemaString(schema),
      () async => null,
    );
    await library.load();
  });
  test(
    'direct prompt carries canonical schema and only selected request data',
    () {
      final text = prompt.build(request, '編集後の希望');
      expect(text.instructions, contains(schema));
      expect(text.instructions, isNot(contains('編集後の希望')));
      expect(text.input, contains('"confirmed_request":"編集後の希望"'));
      expect(text.input, isNot(contains('selected_feedback')));
      expect(() => prompt.build(request, ' '), throwsFormatException);
      final improvement = AiRecipeRequest.improve(
        feedback: feedback,
        validator: FeedbackValidator.fromSchemaStrings(
          feedbackSchemaSource: feedbackSchema,
          recipeSchemaSource: schema,
        ),
      );
      final improvementText = prompt.build(improvement, '追加の希望');
      expect(improvementText.input, contains(jsonEncode(feedback)));
      expect(
        improvementText.instructions,
        isNot(contains(jsonEncode(feedback))),
      );
      expect(improvementText.instructions, contains('next_revision'));
    },
  );
  test(
    'failed answer diagnostics classify format without exposing contents',
    () {
      final cases = <(String, RecipeImportErrorCode, String)>[
        (
          '秘密の説明文 {"password":"secret"}',
          RecipeImportErrorCode.malformedJson,
          '説明文・対応外の囲み',
        ),
        (
          '```\n{"secret":true}\n```',
          RecipeImportErrorCode.malformedJson,
          '説明文・対応外の囲み',
        ),
        (
          '{"private":"secret"',
          RecipeImportErrorCode.malformedJson,
          '本文末尾で途切れ',
        ),
        ('{"private":"secret",}', RecipeImportErrorCode.malformedJson, '構文不正'),
        ('["secret"]', RecipeImportErrorCode.invalidRoot, 'オブジェクト以外'),
        (
          '```json\n{"private":"secret"}\n```',
          RecipeImportErrorCode.schemaViolation,
          '必須情報・形式・参照の不一致',
        ),
      ];
      for (final (source, code, expected) in cases) {
        final diagnostic = describeAiRecipeFailure(source, code);
        expect(diagnostic, contains(expected));
        expect(diagnostic, contains('受信文字: ${source.length}'));
        expect(diagnostic, isNot(contains('secret')));
        expect(diagnostic, isNot(contains('private')));
        expect(diagnostic, isNot(contains('password')));
        expect(diagnostic, isNot(contains('秘密')));
      }
    },
  );
  test(
    'new and improved recipes require identity match and keep active/history',
    () async {
      expect(
        (await prepareAiRecipe(library, request, '普通の回答')).preview,
        isNull,
      );
      expect(store.documents, isEmpty);
      final first = (await prepareAiRecipe(
        library,
        request,
        recipeSource,
      )).preview!;
      expect(store.documents, isEmpty);
      await library.confirmPreparedImport(first);
      final duplicate = (await prepareAiRecipe(
        library,
        request,
        recipeSource,
      )).preview!;
      expect(library.isStoredPreview(duplicate), isTrue);
      library.cancelPreparedImport(duplicate);
      final base = feedback['recipe_snapshot'] as Map<String, dynamic>;
      await library.confirmPreparedImport(
        (await library.prepareImportSource(jsonEncode(base))).preview!,
      );
      final id = (base['recipe'] as Map)['id'] as String;
      await library.setActiveRevision(id, 1);
      final improvement = AiRecipeRequest.improve(
        feedback: feedback,
        validator: FeedbackValidator.fromSchemaStrings(
          feedbackSchemaSource: feedbackSchema,
          recipeSchemaSource: schema,
        ),
      );
      final next = jsonDecode(jsonEncode(base)) as Map<String, dynamic>;
      final recipe = next['recipe'] as Map<String, dynamic>;
      recipe['revision'] =
          (feedback['revision_request'] as Map)['next_revision'];
      recipe['parent_revision'] = 1;
      recipe['id'] = 'wrong';
      expect(
        (await prepareAiRecipe(library, improvement, jsonEncode(next))).preview,
        isNull,
      );
      recipe['id'] = id;
      final preparation = await prepareAiRecipe(
        library,
        improvement,
        jsonEncode(next),
      );
      expect(library.revisionsFor(id), hasLength(1));
      await library.confirmPreparedImport(
        preparation.preview!,
        preserveActive: true,
      );
      expect(library.revisionsFor(id), hasLength(2));
      expect(library.activeRecipeFor(id)!.revision, 1);
      expect(library.latestRecipeFor(id)!.revision, recipe['revision']);
    },
  );
  test(
    'failed active-choice persistence prevents a new AI revision save',
    () async {
      final base = feedback['recipe_snapshot'] as Map<String, dynamic>;
      store.documents.add(base);
      final protected = RecipeLibraryController(
        store,
        _Tags(),
        RecipeValidator.fromSchemaString(schema),
        () async => null,
        recipeVersionStateStore: _FailingVersions(),
      );
      await protected.load();
      final next = jsonDecode(jsonEncode(base)) as Map<String, dynamic>;
      (next['recipe'] as Map)['revision'] = 2;
      (next['recipe'] as Map)['parent_revision'] = 1;
      final preparation = await protected.prepareImportSource(jsonEncode(next));
      final result = await protected.confirmPreparedImport(
        preparation.preview!,
        preserveActive: true,
      );
      expect(result.status, RecipeImportStatus.failed);
      expect(store.documents, hasLength(1));
      expect(
        protected
            .activeRecipeFor((base['recipe'] as Map)['id'] as String)!
            .revision,
        1,
      );
    },
  );
  testWidgets(
    'voice and edit never send; prose rejected; valid reply saves only after confirmation',
    (tester) async {
      library = RecipeLibraryController(
        store,
        _Tags(),
        RecipeValidator.fromSchemaString(schema),
        () async => null,
      );
      await library.load();
      final client = _Client();
      await tester.pumpWidget(
        MaterialApp(
          home: ConnectedRecipeScreen(
            request: request,
            library: library,
            client: client,
            prompt: prompt,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await visible(tester, 'creation_options');
      await tester.tap(find.text('こだわりを追加（任意）'));
      await tester.pumpAndSettle();
      await visible(tester, 'connected_ai_dictate');
      await tester.tap(find.byKey(const Key('connected_ai_dictate')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('音声入力を始める'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('connected_ai_text')),
        '卵を使って安全な料理を一人分',
      );
      expect(client.prompts, isEmpty);
      await visible(tester, 'connected_ai_send');
      await tester.tap(find.byKey(const Key('connected_ai_send')));
      await tester.pumpAndSettle();
      expect(client.prompts, hasLength(1));
      expect(store.documents, isEmpty);
      expect(find.byKey(const Key('connected_ai_save')), findsNothing);
      client.response = recipeSource;
      await tester.tap(find.byKey(const Key('connected_ai_send')));
      await tester.pumpAndSettle();
      expect(store.documents, isEmpty);
      await visible(tester, 'connected_ai_save');
      await tester.tap(find.byKey(const Key('connected_ai_save')));
      await tester.pumpAndSettle();
      expect(store.documents, hasLength(1));
    },
  );
  testWidgets(
    'duplicate sending disabled and exiting cancels late result without saving',
    (tester) async {
      library = RecipeLibraryController(
        store,
        _Tags(),
        RecipeValidator.fromSchemaString(schema),
        () async => null,
      );
      await library.load();
      final client = _Client()..pending = Completer<String>();
      await tester.pumpWidget(
        MaterialApp(
          home: ConnectedRecipeScreen(
            request: request,
            library: library,
            client: client,
            prompt: prompt,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await visible(tester, 'connected_ai_send');
      await tester.tap(find.byKey(const Key('connected_ai_send')));
      await tester.pump();
      expect(find.byKey(const Key('connected_ai_send')), findsNothing);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      client.pending!.complete(recipeSource);
      await tester.pumpAndSettle();
      expect(client.prompts, hasLength(1));
      expect(client.cancels, greaterThanOrEqualTo(1));
      expect(store.documents, isEmpty);
      expect(library.isBusy, isFalse);
    },
  );
}
