import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_cooking_navigator/ui/recipe_revision_navigator.dart';
import 'package:recipe_cooking_navigator/ui/recipe_theme.dart';

void main() {
  testWidgets('card follows the finger, returns, and slides between versions', (
    tester,
  ) async {
    final harness = _NavigatorHarness();
    await tester.pumpWidget(harness.app());
    final card = find.byKey(const Key('recipe_revision_card'));
    final swipe = find.byKey(const Key('recipe_revision_swipe'));
    final center = tester.getCenter(card);
    final start = tester.getCenter(swipe);

    var gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(-22, 0));
    await gesture.moveBy(const Offset(-12, 0));
    await tester.pump();
    expect(tester.getCenter(card).dx, lessThan(center.dx));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(harness.current, 2);
    expect(harness.moves, isEmpty);
    expect(tester.getCenter(card).dx, closeTo(center.dx, 0.1));

    gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(-22, 0));
    await gesture.moveBy(const Offset(-100, 0));
    await tester.pump();
    final draggedX = tester.getCenter(card).dx;
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));
    expect(harness.current, 2);
    expect(tester.getCenter(card).dx, lessThan(draggedX));
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('next_recipe_revision')))
          .onPressed,
      isNull,
    );
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump();
    expect(harness.current, 3);
    expect(tester.getCenter(card).dx, greaterThan(center.dx));
    expect(harness.scroll.positions.length, 1);
    await tester.pumpAndSettle();
    expect(harness.moves, [3]);
    expect(tester.getCenter(card).dx, closeTo(center.dx, 0.1));

    // The last version resists an outward drag and returns without switching.
    await tester.drag(swipe, const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(harness.moves, [3]);
    expect(tester.getCenter(card).dx, closeTo(center.dx, 0.1));

    await tester.tap(find.byKey(const Key('previous_recipe_revision')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));
    expect(tester.getCenter(card).dx, greaterThan(center.dx));
    await tester.pumpAndSettle();
    expect(harness.current, 2);
    expect(harness.moves, [3, 2]);
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(harness.scroll.offset, greaterThan(0));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    harness.scroll.dispose();
  });

  testWidgets('reduced motion changes the version without moving the card', (
    tester,
  ) async {
    final harness = _NavigatorHarness();
    await tester.pumpWidget(harness.app(reducedMotion: true));
    final card = find.byKey(const Key('recipe_revision_card'));
    final center = tester.getCenter(card);
    await tester.drag(
      find.byKey(const Key('recipe_revision_swipe')),
      const Offset(180, 0),
    );
    await tester.pump();
    expect(harness.current, 1);
    expect(harness.moves, [1]);
    expect(tester.getCenter(card), center);
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.getCenter(card), center);
    await tester.pumpWidget(const SizedBox());
    harness.scroll.dispose();
  });

  testWidgets('leaving during the outgoing animation cancels safely', (
    tester,
  ) async {
    final harness = _NavigatorHarness();
    await tester.pumpWidget(harness.app());
    await tester.tap(find.byKey(const Key('next_recipe_revision')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(harness.moves, isEmpty);
    expect(tester.takeException(), isNull);
    harness.scroll.dispose();
  });
}

class _NavigatorHarness {
  int current = 2;
  final moves = <int>[];
  final scroll = ScrollController();

  Widget app({bool reducedMotion = false}) => MaterialApp(
    theme: RecipeTheme.light,
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: Scaffold(
        body: StatefulBuilder(
          builder: (context, update) => RecipeRevisionNavigator(
            revisions: const [1, 2, 3],
            current: current,
            onChanged: (revision) => update(() {
              current = revision;
              moves.add(revision);
            }),
            child: ListView(
              key: ValueKey(current),
              controller: scroll,
              children: [
                Text('レシピ $current'),
                for (var index = 0; index < 30; index++)
                  SizedBox(height: 80, child: Text('工程 $index')),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
