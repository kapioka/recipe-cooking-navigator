import 'package:flutter/material.dart';

/// AI's estimate stays separate from the user's assessment.
class RecipeDifficultyMeter extends StatelessWidget {
  const RecipeDifficultyMeter({required this.difficulty, super.key});

  final int difficulty;

  static const _colors = [
    Color(0xFF9FBCA6),
    Color(0xFF7DA78C),
    Color(0xFFC6AD62),
    Color(0xFFD49870),
    Color(0xFFC47F7F),
  ];

  @override
  Widget build(BuildContext context) {
    final level = difficulty.clamp(1, 5);
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: 'AIの難易度目安、5段階中$level',
      child: ExcludeSemantics(
        child: Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('AIの難易度目安', style: Theme.of(context).textTheme.bodySmall),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < 5; index++) ...[
                  if (index != 0) const SizedBox(width: 4),
                  Container(
                    width: 14,
                    height: 9,
                    decoration: BoxDecoration(
                      color: index < level
                          ? _colors[level - 1]
                          : colors.surface,
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(
                        color: index < level
                            ? _colors[level - 1]
                            : colors.outlineVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
