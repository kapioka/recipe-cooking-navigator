import 'package:flutter/widgets.dart';

import '../application/preference_controller.dart';

class PreferenceControllerScope extends InheritedWidget {
  const PreferenceControllerScope({
    required this.controller,
    required super.child,
    super.key,
  });
  final PreferenceController controller;
  static PreferenceController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PreferenceControllerScope>()
      ?.controller;
  @override
  bool updateShouldNotify(PreferenceControllerScope oldWidget) =>
      controller != oldWidget.controller;
}
