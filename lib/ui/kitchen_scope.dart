import 'package:flutter/widgets.dart';

import '../application/kitchen_controller.dart';

typedef KitchenOperation = Future<bool> Function(
  void Function(KitchenController) operation,
);

/// Exposes the single Kitchen timer owner to nested Recipe/Cooking routes.
class KitchenScope extends InheritedNotifier<KitchenController> {
  const KitchenScope({
    required KitchenController controller,
    required this.perform,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  final KitchenOperation perform;

  KitchenController get controller => notifier!;

  static KitchenScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<KitchenScope>();

  static bool contains(BuildContext context) => maybeOf(context) != null;
}
