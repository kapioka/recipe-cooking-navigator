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

class _RecipeRevisionNavigatorState extends State<RecipeRevisionNavigator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slide = AnimationController.unbounded(
    vsync: this,
  );
  double _drag = 0;
  double _cardWidth = 1;
  bool _moving = false;

  bool _canMove(int direction) {
    final next = widget.revisions.indexOf(widget.current) + direction;
    return widget.enabled && next >= 0 && next < widget.revisions.length;
  }

  Future<void> _move(int direction) async {
    if (_moving) return;
    if (!_canMove(direction)) {
      await _returnToCenter();
      return;
    }
    final from = widget.current;
    final next = widget.revisions[widget.revisions.indexOf(from) + direction];
    if (MediaQuery.disableAnimationsOf(context)) {
      _slide.value = 0;
      widget.onChanged(next);
      return;
    }
    setState(() => _moving = true);
    try {
      // Move the current card out first. Only one scrollable recipe is mounted,
      // including on review screens that own a shared ScrollController.
      await _slide
          .animateTo(
            -direction.toDouble(),
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeInCubic,
          )
          .orCancel;
      if (!mounted) return;
      if (!widget.enabled || widget.current != from) return;
      _slide.value = direction.toDouble();
      widget.onChanged(next);
      await _slide
          .animateTo(
            0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          )
          .orCancel;
    } on TickerCanceled {
      // Leaving the screen cancels the transition without changing a version.
    } finally {
      if (mounted) {
        _slide.value = 0;
        setState(() => _moving = false);
      }
    }
  }

  Future<void> _returnToCenter() async {
    if (_moving || _slide.value == 0) return;
    setState(() => _moving = true);
    try {
      await _slide
          .animateTo(
            0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          )
          .orCancel;
    } on TickerCanceled {
      // The navigator may be disposed during the return animation.
    } finally {
      if (mounted) setState(() => _moving = false);
    }
  }

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final position = widget.revisions.indexOf(widget.current);
    return GestureDetector(
      key: const Key('recipe_revision_swipe'),
      onHorizontalDragStart: (_) => _drag = 0,
      onHorizontalDragUpdate: (event) {
        if (_moving || !widget.enabled) return;
        _drag += event.delta.dx;
        if (MediaQuery.disableAnimationsOf(context)) return;
        final direction = _drag > 0 ? -1 : 1;
        final resistance = _canMove(direction) ? 1.0 : 0.16;
        _slide.value = (_drag / _cardWidth * resistance).clamp(-0.85, 0.85);
      },
      onHorizontalDragEnd: (_) {
        if (_moving || !widget.enabled) return;
        if (_drag.abs() >= 48) {
          _move(_drag > 0 ? -1 : 1);
        } else {
          _returnToCenter();
        }
      },
      onHorizontalDragCancel: _returnToCenter,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  key: const Key('previous_recipe_revision'),
                  tooltip: '前のバージョンを見る',
                  onPressed: widget.enabled && !_moving && position > 0
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
                          !_moving &&
                          position >= 0 &&
                          position < widget.revisions.length - 1
                      ? () => _move(1)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                _cardWidth = constraints.maxWidth;
                return ClipRect(
                  child: AnimatedBuilder(
                    animation: _slide,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                      child: Material(
                        key: const Key('recipe_revision_card'),
                        color: RecipeTheme.cream,
                        elevation: 1,
                        shadowColor: RecipeTheme.ink.withValues(alpha: 0.12),
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                          side: const BorderSide(color: RecipeTheme.outline),
                        ),
                        child: widget.child,
                      ),
                    ),
                    builder: (context, child) => IgnorePointer(
                      ignoring: _moving,
                      child: FractionalTranslation(
                        translation: Offset(_slide.value, 0),
                        child: Transform.scale(
                          scale: 1 - 0.025 * _slide.value.abs().clamp(0, 1),
                          child: child,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
