import 'dart:convert';

import 'recipe_amount.dart';

const servingsScalingAlgorithm = 'servings-v2.0';

class CookingContext {
  CookingContext({
    required this.targetServings,
    required this.resolvedAmounts,
    this.scalingAlgorithm = servingsScalingAlgorithm,
  });

  factory CookingContext.fromJson(Map<String, dynamic> json) => CookingContext(
    targetServings: json['target_servings'] as int,
    scalingAlgorithm: json['scaling_algorithm'] as String,
    resolvedAmounts: (json['resolved_amounts'] as List<dynamic>)
        .map(
          (item) =>
              ResolvedAmount.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false),
  );

  final int targetServings;
  final String scalingAlgorithm;
  final List<ResolvedAmount> resolvedAmounts;

  Map<String, ResolvedAmount> get byId => {
    for (final amount in resolvedAmounts) amount.amountId: amount,
  };

  Map<String, dynamic> toJson() => {
    'target_servings': targetServings,
    'scaling_algorithm': scalingAlgorithm,
    'resolved_amounts': resolvedAmounts
        .map((amount) => amount.toJson())
        .toList(growable: false),
  };

  bool jsonEquals(CookingContext other) =>
      jsonEncode(toJson()) == jsonEncode(other.toJson());
}
