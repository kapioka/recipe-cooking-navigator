import 'package:flutter/material.dart';

import 'recipe_theme.dart';

Future<bool> confirmFutureRecipe(BuildContext context, int revision) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('バージョン $revisionを今後使いますか？'),
        content: const Text('次回のレシピ表示と、最初から調理するときに使います。過去のレシピと調理途中の記録は残ります。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            key: const Key('confirm_future_recipe'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('今後使う'),
          ),
        ],
      ),
    ) ??
    false;

/// Browsing never changes the active recipe; the explicit save action owns that.
class RecipeRevisionNavigator extends StatefulWidget {
  const RecipeRevisionNavigator({
    required this.revisions,
    required this.current,
    required this.onChanged,
    required this.child,
    this.enabled = true,
    super.key,
  });
  final List<int> revisions;
  final int current;
  final ValueChanged<int> onChanged;
  final Widget child;
  final bool enabled;
  @override
  State<RecipeRevisionNavigator> createState() =>
      _RecipeRevisionNavigatorState();
}

class _RecipeRevisionNavigatorState extends State<RecipeRevisionNavigator> {
  double _drag = 0;
  void _move(int direction) {
    final next = widget.revisions.indexOf(widget.current) + direction;
    if (widget.enabled && next >= 0 && next < widget.revisions.length) {
      widget.onChanged(widget.revisions[next]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final position = widget.revisions.indexOf(widget.current);
    return GestureDetector(
      key: const Key('recipe_revision_swipe'),
      onHorizontalDragStart: (_) => _drag = 0,
      onHorizontalDragUpdate: (event) => _drag += event.delta.dx,
      onHorizontalDragEnd: (_) {
        if (_drag.abs() >= 48) _move(_drag > 0 ? -1 : 1);
      },
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  key: const Key('previous_recipe_revision'),
                  tooltip: '前のバージョンを見る',
                  onPressed: widget.enabled && position > 0
                      ? () => _move(-1)
                      : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      '表示中: バージョン ${widget.current}\n左右スワイプで見比べる',
                      textAlign: TextAlign.center,
                      style: RecipeTheme.readingNote,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('next_recipe_revision'),
                  tooltip: '次のバージョンを見る',
                  onPressed:
                      widget.enabled &&
                          position >= 0 &&
                          position < widget.revisions.length - 1
                      ? () => _move(1)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
          Expanded(child: widget.child),
        ],
      ),
    );
  }
}
