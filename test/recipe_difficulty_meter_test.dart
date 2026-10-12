import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_cooking_navigator/ui/recipe_difficulty_meter.dart';
import 'package:recipe_cooking_navigator/ui/recipe_theme.dart';

void main() {
  testWidgets(
    'five segments convey each level without visible numeric scores',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final activeColors = <Color>{};
        for (var level = 1; level <= 5; level++) {
          await tester.pumpWidget(
            MaterialApp(
              theme: RecipeTheme.light,
              home: Scaffold(body: RecipeDifficultyMeter(difficulty: level)),
            ),
          );
          expect(find.text('AIの難易度目安'), findsOneWidget);
          expect(find.text('$level/5'), findsNothing);
          expect(find.bySemanticsLabel('AIの難易度目安、5段階中$level'), findsOneWidget);
          final segments = tester.widgetList<Container>(
            find.descendant(
              of: find.byType(RecipeDifficultyMeter),
              matching: find.byType(Container),
            ),
          );
          expect(segments, hasLength(5));
          final filled = segments.where(
            (segment) =>
                (segment.decoration as BoxDecoration).color !=
                RecipeTheme.light.colorScheme.surface,
          );
          expect(filled, hasLength(level));
          activeColors.add((filled.first.decoration as BoxDecoration).color!);
          expect(tester.takeException(), isNull);
        }
        expect(activeColors, hasLength(5));
      } finally {
        semantics.dispose();
      }
    },
  );
}
