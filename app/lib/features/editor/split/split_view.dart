import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../ui/app_theme.dart';

/// Lays out the workspace's editors: [primary] alone, or beside
/// [secondary] with a draggable divider ([fraction] of the width for the
/// primary). [solo] shows one of them alone (presentation) while the other
/// stays alive offstage. The primary keeps its place in the tree in every
/// layout, so opening or closing the split never rebuilds its editor.
class SplitView extends StatelessWidget {
  const SplitView({
    super.key,
    required this.primary,
    this.secondary,
    required this.fraction,
    required this.onFraction,
    this.onFractionEnd,
    this.solo,
  });

  final Widget primary;
  final Widget? secondary;
  final double fraction;
  final ValueChanged<double> onFraction;
  final VoidCallback? onFractionEnd;

  /// Show only the primary (false) or only the secondary (true).
  final bool? solo;

  /// Width of the divider's touch target.
  static const double dividerWidth = 12;

  /// Narrowest a pane gets.
  static const double minPane = 320;

  /// Whether a screen of [size] can show two panes: tablets in landscape
  /// and desktops — not phones, not portrait tablets.
  static bool fits(Size size) => size.width >= 900 && size.shortestSide >= 560;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final secondary = this.secondary;
        final split = secondary != null && solo == null;
        final room = width - dividerWidth;
        final left = split
            ? (room * fraction).clamp(minPane, (room - minPane).clamp(minPane, room))
            : width;
        final media = MediaQuery.of(context);
        return Stack(
          children: [
            Positioned(
              key: const ValueKey('primary-pane'),
              left: 0,
              top: 0,
              bottom: 0,
              width: solo == true ? width : left,
              child: Offstage(
                offstage: solo == true,
                child: MediaQuery(
                  data: split ? media.removePadding(removeRight: true) : media,
                  child: primary,
                ),
              ),
            ),
            if (secondary != null) ...[
              if (split)
                Positioned(
                  key: const ValueKey('split-divider'),
                  left: left,
                  top: 0,
                  bottom: 0,
                  width: dividerWidth,
                  child: _Divider(
                    onDrag: (dx) => onFraction((left + dx) / room),
                    onEnd: onFractionEnd,
                    onReset: () {
                      onFraction(0.5);
                      onFractionEnd?.call();
                    },
                    fraction: fraction,
                  ),
                ),
              Positioned(
                key: const ValueKey('secondary-pane'),
                left: solo == false ? 0 : (solo == true ? 0 : left + dividerWidth),
                top: 0,
                bottom: 0,
                width: solo == null ? width - left - dividerWidth : width,
                child: Offstage(
                  offstage: solo == false,
                  child: MediaQuery(
                    data: split ? media.removePadding(removeLeft: true) : media,
                    child: secondary,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// The bar between the panes: drag to resize, double-tap for halves;
/// ← / → when focused.
class _Divider extends StatelessWidget {
  const _Divider({
    required this.onDrag,
    required this.onEnd,
    required this.onReset,
    required this.fraction,
  });

  final ValueChanged<double> onDrag;
  final VoidCallback? onEnd;
  final VoidCallback onReset;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Split view divider',
      value: '${(fraction * 100).round()}%',
      increasedValue: '${((fraction + 0.05) * 100).round()}%',
      decreasedValue: '${((fraction - 0.05) * 100).round()}%',
      onIncrease: () => _step(context, 1),
      onDecrease: () => _step(context, -1),
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) return _step(context, -1);
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) return _step(context, 1);
          return KeyEventResult.ignored;
        },
        child: Tooltip(
          message: 'Drag to resize · double-tap for halves',
          waitDuration: const Duration(seconds: 1),
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
              onHorizontalDragEnd: (_) => onEnd?.call(),
              onDoubleTap: onReset,
              child: ColoredBox(
                color: scheme.surfaceContainerHigh,
                child: Center(
                  child: Container(
                    width: 4,
                    height: 40,
                    decoration: BoxDecoration(
                      color: scheme.outline,
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  KeyEventResult _step(BuildContext context, int direction) {
    final box = context.findRenderObject() as RenderBox?;
    final parent = box?.parent;
    final total = parent is RenderBox && parent.hasSize ? parent.size.width : 1000.0;
    onDrag(direction * 0.05 * total);
    onEnd?.call();
    return KeyEventResult.handled;
  }
}
