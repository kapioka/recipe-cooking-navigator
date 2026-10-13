import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_cooking_navigator/application/recipe_library_controller.dart';
import 'package:recipe_cooking_navigator/domain/recipe_comparison.dart';
import 'package:recipe_cooking_navigator/domain/recipe_document.dart';
import 'package:recipe_cooking_navigator/domain/recipe_validator.dart';
import 'package:recipe_cooking_navigator/ui/recipe_changes_card.dart';
import 'package:recipe_cooking_navigator/ui/recipe_compared_text.dart';
import 'package:recipe_cooking_navigator/ui/recipe_preview_content.dart';
import 'package:recipe_cooking_navigator/ui/recipe_theme.dart';

void main() {
  late RecipeDocument before, after;
  late RecipeComparison comparison;
  late String stepId, storage;
  setUpAll(() async {
    final validator = RecipeValidator.fromSchemaString(
      await File('schemas/recipe-v2.schema.json').readAsString(),
    );
    final original = jsonDecode(
      await File('examples/recipe-example.json').readAsString(),
    ) as Map<String, dynamic>;
    final next = jsonDecode(jsonEncode(original)) as Map<String, dynamic>;
    final recipe = next['recipe'] as Map;
    recipe['revision'] = 2;
    recipe['parent_revision'] = 1;
    final step = recipe['stages'][0]['steps'][0] as Map;
    stepId = step['id'] as String;
    step['timer_seconds'] = 150;
    step['instruction'] = [
      {'type': 'text', 'text': '弱火で150秒焼き、焦げないよう様子を見ながら皿に盛り付ける。'},
    ];
    recipe.remove('storage_note');
    before = validator.validateDocument(original);
    after = validator.validateDocument(next);
    storage = before
        .renderText(
          before.recipeData['storage_note'] as List,
          before.contextFor(before.servings),
        )
        .displayText;
    comparison = RecipeComparison(before, after);
  });

  Future<void> openList(WidgetTester tester) async {
    final header = find.text('変更点（${comparison.changes.length}項目）');
    await tester.ensureVisible(header);
    await tester.tap(header);
    await tester.pumpAndSettle();
  }

  Widget app(Widget child) => MaterialApp(
    theme: RecipeTheme.light,
    home: Scaffold(body: ListView(children: [child])),
  );

  testWidgets(
    'compact rows keep long text and previous values behind explicit details',
    (tester) async {
      await tester.pumpWidget(
        app(RecipeChangesCard(comparison: comparison, browsing: true)),
      );
      expect(find.text(storage), findsNothing);
      expect(find.text('120秒 → 150秒'), findsNothing);
      await openList(tester);
      expect(find.text('120秒 → 150秒'), findsOneWidget);
      final row = find.byKey(ValueKey('compact_change_timer:$stepId'));
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.text('表示中 · バージョン 2'), findsOneWidget);
      expect(find.text('比較元 · バージョン 1'), findsNothing);
      await tester.tap(find.text('変更前を見る'));
      await tester.pumpAndSettle();
      expect(find.text('比較元 · バージョン 1'), findsOneWidget);
      expect(find.text('120秒'), findsOneWidget);
      expect(find.text('150秒'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'deleted content opens in full and cannot vanish from comparison',
    (tester) async {
      await tester.pumpWidget(app(RecipeChangesCard(comparison: comparison)));
      await openList(tester);
      final row = find.byKey(const ValueKey('compact_change_storage'));
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.text('表示中にはありません'), findsOneWidget);
      expect(find.text(storage), findsOneWidget);
      final text = tester.widget<RecipeComparedText>(
        find.byType(RecipeComparedText),
      );
      expect(text.baseline, isTrue);
      expect(text.compared, isTrue);
    },
  );

  for (final width in [320.0, 412.0]) {
    testWidgets(
      'summary jumps to inline changes without repeating before text at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1120);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: RecipeTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: ListView(
                children: [
                  RecipePreviewContent(
                    preview: RecipeImportPreview.forDisplay(after),
                    before: RecipeImportPreview.forDisplay(before),
                    saved: true,
                    historyComparison: true,
                  ),
                ],
              ),
            ),
          ),
        );
        final chip = find.byKey(const ValueKey('change_section_調理の工程'));
        await tester.ensureVisible(chip);
        await tester.tap(chip);
        await tester.pumpAndSettle();
        final field = find.byKey(ValueKey('step_text_timer:$stepId'));
        final timer = tester.widget<RecipeComparedText>(field);
        expect(timer.text, '150秒');
        expect(timer.before, '120秒');
        expect(timer.compared, isTrue);
        final scroll = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        expect(scroll.position.pixels, greaterThan(0));
        expect(find.text('120秒'), findsNothing);
        final serializedBefore = jsonEncode(before.raw),
            serializedAfter = jsonEncode(after.raw);
        for (var index = 0; index < 18; index++) {
          await tester.drag(find.byType(ListView), const Offset(0, -300));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        expect(jsonEncode(before.raw), serializedBefore);
        expect(jsonEncode(after.raw), serializedAfter);
      },
    );
  }
}
