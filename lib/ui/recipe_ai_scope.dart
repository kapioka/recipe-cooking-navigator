import 'package:flutter/widgets.dart';

import '../application/recipe_ai_session.dart';

class RecipeAiScope extends InheritedWidget {
  const RecipeAiScope({required this.session, required super.child, super.key});
  final RecipeAiSession session;
  static RecipeAiSession? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RecipeAiScope>()?.session;
  @override
  bool updateShouldNotify(RecipeAiScope oldWidget) =>
      session != oldWidget.session;
}
