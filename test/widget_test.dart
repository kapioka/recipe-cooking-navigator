import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_cooking_navigator/main.dart';

void main() {
  testWidgets('shows the application name', (tester) async {
    await tester.pumpWidget(const RecipeCookingNavigatorApp());

    expect(find.text('Recipe Cooking Navigator'), findsOneWidget);
  });
}
