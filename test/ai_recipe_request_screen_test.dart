import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_cooking_navigator/application/recipe_library_controller.dart';
import 'package:recipe_cooking_navigator/data/recipe_document_store.dart';
import 'package:recipe_cooking_navigator/data/recipe_tag_store.dart';
import 'package:recipe_cooking_navigator/domain/ai_recipe_request.dart';
import 'package:recipe_cooking_navigator/domain/recipe_validator.dart';
import 'package:recipe_cooking_navigator/platform/ai_request_platform.dart';
import 'package:recipe_cooking_navigator/ui/ai_recipe_request_screen.dart';
import 'package:recipe_cooking_navigator/ui/home_screen.dart';

class _Platform implements AiRequestPlatform {
  final List<String> sent = [];
  bool failOpen = false;
  @override
  Future<void> share(String request) async {
    sent.add(request);
  }

  @override
  Future<void> openChatGpt() async {
    if (failOpen) throw StateError('unavailable');
  }
}

class _Recipes implements RecipeDocumentStore {
  final documents = <Map<String, dynamic>>[];
  @override
  Future<List<Map<String, dynamic>>> loadDocuments() async => documents;
  @override
  Future<StoreRecipeResult> saveDocument(Map<String, dynamic> document) async {
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

void main() {
  late String schema;
  late String source;
  setUpAll(() async {
    schema = await File('schemas/recipe-v2.schema.json').readAsString();
    source = await File('examples/recipe-example.json').readAsString();
  });
  testWidgets(
    'nothing is sent before preview and explicit action, copy survives open failure',
    (tester) async {
      final platform = _Platform()..failOpen = true;
      String? clipboard;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboard = (call.arguments as Map)['text'] as String;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AiRecipeRequestScreen(platform: platform, publicReady: true),
        ),
      );
      await tester.enterText(find.byKey(const Key('ai_食材')), '米、卵');
      expect(platform.sent, isEmpty);
      await tester.ensureVisible(find.text('依頼内容を確認'));
      await tester.tap(find.text('依頼内容を確認'));
      await tester.pumpAndSettle();
      expect(platform.sent, isEmpty);
      await tester.scrollUntilVisible(
        find.byKey(const Key('copy_ai_request')),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.byKey(const Key('copy_ai_request')));
      await tester.pumpAndSettle();
      expect(clipboard, contains('米、卵'));
      await tester.scrollUntilVisible(
        find.textContaining('コピー済みです'),
        100,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.textContaining('コピー済みです'), findsOneWidget);
      expect(platform.sent, isEmpty);
      await tester.ensureVisible(find.byKey(const Key('share_ai_request')));
      await tester.tap(find.byKey(const Key('share_ai_request')));
      await tester.pumpAndSettle();
      expect(platform.sent, hasLength(1));
    },
  );

  testWidgets(
    'publication gate prevents sending incompatible public requests',
    (tester) async {
      final platform = _Platform();
      final request = AiRecipeRequest.generate(
        ingredients: '米',
        servings: 2,
        utensils: '',
        taste: '',
        timeMinutes: 30,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AiRecipeRequestScreen(
            platform: platform,
            improvementRequest: request,
          ),
        ),
      );
      expect(find.byKey(const Key('ai_publication_pending')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('share_ai_request')));
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('share_ai_request')))
            .onPressed,
        isNull,
      );
      expect(platform.sent, isEmpty);
    },
  );

  testWidgets(
    'paste preview and cancellation never save; confirmation saves via existing store',
    (tester) async {
      final store = _Recipes();
      final controller = RecipeLibraryController(
        store,
        _Tags(),
        RecipeValidator.fromSchemaString(schema),
        () async => null,
      );
      await controller.load();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(home: HomeScreen(controller: controller)),
      );
      for (final confirm in [false, true]) {
        await tester.tap(find.byKey(const Key('paste_recipe')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('paste_recipe_source')),
          '```json\n$source\n```',
        );
        await tester.tap(find.byKey(const Key('preview_pasted_recipe')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(await store.loadDocuments(), isEmpty);
        await tester.tap(
          find.byKey(
            Key(confirm ? 'confirm_recipe_import' : 'cancel_recipe_import'),
          ),
        );
        await tester.pumpAndSettle();
        expect(await store.loadDocuments(), confirm ? hasLength(1) : isEmpty);
      }
    },
  );
}
