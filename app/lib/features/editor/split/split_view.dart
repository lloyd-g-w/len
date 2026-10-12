import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../ui/app_theme.dart';

/// Lays out the workspace's editors: [primary] alone, or beside
/// [secondary] with a draggable divider ([fraction] of the width for the
/// primary). [solo] shows one of them alone (presentation, or the screen
/// too small for two) while the other stays alive offstage — without
/// focus or tickers. The primary keeps its place in the tree in every
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

  /// Whether the pane [context] is in is parked (alive but not shown).
  static bool parkedOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ParkedScope>()?.parked ?? false;

  /// The primary pane's width, for the secondary pane [context] is in while
  /// both are shown (null otherwise): its top bar lines up with the
  /// primary's.
  static double? primaryWidthOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ParkedScope>()?.primaryWidth;

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
              child: _Parked(
                parked: solo == true,
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
                child: _Parked(
                  parked: solo == false,
                  primaryWidth: split ? left : null,
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

/// A pane that, while [parked], stays alive (its editor keeps its session,
/// undo and a running recording) but is not shown, takes no keyboard
/// focus and runs no animations.
class _Parked extends StatelessWidget {
  const _Parked({required this.parked, required this.child, this.primaryWidth});

  final bool parked;
  final double? primaryWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) => Offstage(
    offstage: parked,
    child: ExcludeFocus(
      excluding: parked,
      child: TickerMode(
        enabled: !parked,
        child: _ParkedScope(parked: parked, primaryWidth: primaryWidth, child: child),
      ),
    ),
  );
}

class _ParkedScope extends InheritedWidget {
  const _ParkedScope({required this.parked, required super.child, this.primaryWidth});

  final bool parked;
  final double? primaryWidth;

  @override
  bool updateShouldNotify(_ParkedScope old) =>
      old.parked != parked || old.primaryWidth != primaryWidth;
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
