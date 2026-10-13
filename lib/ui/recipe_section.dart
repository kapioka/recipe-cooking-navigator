import 'package:flutter/material.dart';

import 'recipe_theme.dart';

/// A single content group in the shared recipe-book visual style.
class RecipeSection extends StatelessWidget {
  const RecipeSection({
    required this.children,
    this.title,
    this.icon,
    this.titleStyle,
    this.color = Colors.white,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(bottom: 16),
    super.key,
  });

  final List<Widget> children;
  final String? title;
  final IconData? icon;
  final TextStyle? titleStyle;
  final Color color;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) => Padding(
    padding: margin,
    child: Material(
      color: color,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Semantics(
                header: true,
                child: Row(
                  children: [
                    if (icon != null) ...[
                      Icon(icon, color: RecipeTheme.forest, size: 22),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Text(
                        title!,
                        style:
                            titleStyle ??
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: RecipeTheme.forest,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            ...children,
          ],
        ),
      ),
    ),
  );
}
