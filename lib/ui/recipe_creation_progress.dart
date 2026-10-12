import 'package:flutter/material.dart';

import 'recipe_theme.dart';

class RecipeCreationProgress extends StatelessWidget {
  const RecipeCreationProgress({required this.currentStep, super.key});
  final int currentStep;
  static const labels = ['条件', '作成中', '内容確認'];

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: '$currentStep ${labels[currentStep - 1]} ／ 条件 → 作成中 → 内容確認',
    excludeSemantics: true,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < labels.length; index++)
            Expanded(
              child: Column(
                children: [
                  Icon(
                    index + 1 == currentStep
                        ? Icons.circle
                        : Icons.circle_outlined,
                    size: 16,
                    color: index + 1 == currentStep
                        ? RecipeTheme.forest
                        : Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    labels[index],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: index + 1 == currentStep
                          ? RecipeTheme.forest
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: index + 1 == currentStep
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
