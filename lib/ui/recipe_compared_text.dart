import 'package:flutter/material.dart';

import '../domain/recipe_text_diff.dart';
import 'recipe_theme.dart';

/// Highlight changed phrases/values; shared text retains its normal style.
class RecipeComparedText extends StatelessWidget {
  const RecipeComparedText({
    required this.text,
    this.before,
    this.compared = false,
    this.prefix = '',
    this.baseline = false,
    this.style,
    this.textAlign,
    super.key,
  });
  final String text, prefix;
  final String? before;
  final bool compared, baseline;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final normal = style ?? RecipeTheme.readingBody;
    if (!compared) {
      return Text('$prefix$text', style: normal, textAlign: textAlign);
    }
    final diff = baseline
        ? RecipeTextDiff(text, before ?? '')
        : RecipeTextDiff(before ?? '', text);
    final parts = baseline ? diff.beforeFragments : diff.afterFragments;
    return Text.rich(
      TextSpan(
        children: [
          if (prefix.isNotEmpty) TextSpan(text: prefix),
          for (final part in parts)
            TextSpan(
              text: part.text,
              style: part.changed
                  ? TextStyle(
                      backgroundColor: baseline
                          ? const Color(0xFFF4E4E2)
                          : RecipeTheme.sage,
                      color: baseline
                          ? const Color(0xFF793F3B)
                          : RecipeTheme.forest,
                      fontWeight: FontWeight.w600,
                    )
                  : null,
            ),
        ],
      ),
      style: normal,
      textAlign: textAlign,
    );
  }
}
