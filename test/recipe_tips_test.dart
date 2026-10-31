import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_cooking_navigator/application/recipe_library_controller.dart';
import 'package:recipe_cooking_navigator/data/cooking_store.dart';
import 'package:recipe_cooking_navigator/data/preparation_checklist_store.dart';
import 'package:recipe_cooking_navigator/domain/recipe_validator.dart';
import 'package:recipe_cooking_navigator/ui/cooking_screen.dart';
import 'package:recipe_cooking_navigator/ui/recipe_preview_content.dart';
import 'package:recipe_cooking_navigator/ui/recipe_theme.dart';
import 'package:recipe_cooking_navigator/ui/recipe_tips.dart';

void main() {
  late String schema;
  late String source;
  final calls = <MethodCall>[];

  setUpAll(() async {
    schema = await File('schemas/recipe-v2.schema.json').readAsString();
    source = await File('examples/recipe-example.json').readAsString();
  });
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('recipe/cooking'), (
          call,
        ) async {
          calls.add(call);
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('recipe/cooking'), null);
  });

  testWidgets(
    'tips stay optional during preparation and cooking, outside TTS',
    (tester) async {
      final validator = RecipeValidator.fromSchemaString(schema);
      final data = jsonDecode(source) as Map<String, dynamic>;
      data['recipe']['adjustments'] = [
        {
          'condition': [
            {'type': 'text', 'text': '肉が重なるとき'},
          ],
          'action': [
            {'type': 'text', 'text': '2回に分けて焼くと、水っぽくなりにくい。'},
          ],
        },
      ];
      final recipe = validator.validateDocument(data);
      final original = jsonEncode(recipe.raw);
      final store = CookingStore(null, validator);
      await store.markHelpSeen();
      await tester.pumpWidget(
        MaterialApp(
          theme: RecipeTheme.light,
          home: CookingScreen(
            recipe: recipe,
            store: store,
            preparationStore: PreparationChecklistStore(),
            initialIndex: 0,
            cookingContext: recipe.contextFor(2),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('下準備'), findsOneWidget);
      expect(find.text('肉が重なるとき'), findsNothing);
      await tester.scrollUntilVisible(find.text('コツ・失敗対策'), 250);
      await tester.tap(find.text('コツ・失敗対策'));
      await tester.pumpAndSettle();
      expect(find.text('肉が重なるとき'), findsOneWidget);

      // Starting cooking never requires opening or acknowledging the tips.
      await tester.tap(find.byKey(const Key('begin_cooking_steps')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cooking_step_title')), findsOneWidget);
      expect(find.text('肉が重なるとき'), findsNothing);
      await tester.tap(find.byKey(const Key('speak_button')));
      await tester.pump();
      final speech =
          calls.lastWhere((call) => call.method == 'speak').arguments as String;
      expect(
        speech,
        contains(
          recipe
              .renderText(
                recipe.steps.first['instruction'] as List,
                recipe.contextFor(2),
              )
              .speechText,
        ),
      );
      expect(speech, isNot(contains('肉が重なるとき')));
      expect(speech, isNot(contains('水っぽく')));
      await tester.scrollUntilVisible(
        find.text('コツ・失敗対策'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('コツ・失敗対策'));
      await tester.pumpAndSettle();
      expect(find.text('肉が重なるとき'), findsOneWidget);
      expect(jsonEncode(recipe.raw), original);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('new recipe preview shows separate tips before saving', (
    tester,
  ) async {
    final recipe = RecipeValidator.fromSchemaString(schema)
        .validateSource(source);
    final preview = RecipeImportPreview.forDisplay(recipe);
    expect(preview.adjustmentDetails, isNotEmpty);
    await tester.pumpWidget(
      MaterialApp(
        theme: RecipeTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: RecipePreviewContent(preview: preview),
          ),
        ),
      ),
    );
    await tester.scrollUntilVisible(find.text('コツ・失敗対策'), 300);
    expect(find.text(preview.adjustmentDetails.first), findsOneWidget);
    expect(find.text('調理・保存の注意'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recipes without tips do not show an empty control', (
    tester,
  ) async {
    final data = jsonDecode(source) as Map<String, dynamic>;
    data['recipe']['adjustments'] = [];
    final recipe = RecipeValidator.fromSchemaString(schema)
        .validateDocument(data);
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeTips(recipe: recipe, cookingContext: recipe.contextFor(2)),
      ),
    );
    expect(find.byType(ExpansionTile), findsNothing);
  });
}
