import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../ink/input/stylus_buttons.dart';
import '../../../ui/app_theme.dart';

/// The zoom box's inner edge (its top; its bottom when it docks at the
/// top), by which its height is dragged: two ticks in
/// the paper's pattern colour (the grips of the floating palette and the
/// split divider), a row-resize cursor and semantic steps. It paints only;
/// the box routes the pointers ([BoxHeightDrag]), so a stylus writing up
/// to the edge still writes.
class ZoomBoxGrip extends StatelessWidget {
  const ZoomBoxGrip({super.key, required this.color, required this.onStep, this.atBottom = false});

  /// Whether the grip lies along the box's bottom edge.
  final bool atBottom;

  /// The ticks' colour (the paper's pattern).
  final Color color;

  /// Grows (positive) or shrinks the box by a step (semantic actions).
  final ValueChanged<double> onStep;

  /// How deep into the box the edge takes a finger or the mouse.
  static double reach(BuildContext context) => Targets.touchFirst ? Gaps.xl : Gaps.md;

  /// A semantic step.
  static const double step = Gaps.xl;

  @override
  Widget build(BuildContext context) {
    Widget tick() => Container(width: Gaps.lg, height: Hairline.width, color: color);
    return Semantics(
      // A node of its own: merged into the editor's focused node, its steps
      // made the whole editor an adjustable (on the web a range input,
      // which took the keyboard focus away from the editor).
      container: true,
      label: 'Zoom window height',
      hint: 'Drag the edge to resize',
      onIncrease: () => onStep(step),
      onDecrease: () => onStep(-step),
      child: MouseRegion(
        // Translucent: the box's paper under it still takes the pointers.
        hitTestBehavior: HitTestBehavior.translucent,
        opaque: false,
        cursor: SystemMouseCursors.resizeRow,
        child: SizedBox(
          height: reach(context),
          child: Align(
            alignment: atBottom ? Alignment.bottomCenter : Alignment.topCenter,
            child: Padding(
              padding: EdgeInsets.only(top: atBottom ? 0 : Gaps.xs, bottom: atBottom ? Gaps.xs : 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  tick(),
                  const SizedBox(height: Gaps.xxs),
                  tick(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A finger or mouse dragging the box's inner edge: the height it asks
/// for. A stylus never resizes (it writes to the edge).
class BoxHeightDrag {
  int? _pointer;
  double _fromY = 0, _fromHeight = 0;

  /// Whether the edge is the bottom one (the box docks at the top): the
  /// box grows downwards.
  bool _down = false;

  /// Whether a drag is under way.
  bool get active => _pointer != null;

  /// Starts a drag if [e] lands within [reach] of the inner edge of the
  /// box's paper, [paper] pixels high ([atBottom]: its bottom edge), the
  /// box being [height] high; returns whether it did.
  bool start(
    PointerDownEvent e, {
    required double reach,
    required double paper,
    required double height,
    bool atBottom = false,
  }) {
    if (_pointer != null || isStylusKind(e.kind)) return false;
    final y = e.localPosition.dy;
    if (atBottom ? y < paper - reach : y > reach) return false;
    if (e.kind == PointerDeviceKind.mouse && e.buttons != kPrimaryButton) return false;
    _pointer = e.pointer;
    _down = atBottom;
    _fromY = e.position.dy;
    _fromHeight = height;
    return true;
  }

  /// The height [e] asks for, or null when it is not the drag's pointer.
  double? move(PointerMoveEvent e) =>
      e.pointer == _pointer ? _fromHeight + (e.position.dy - _fromY) * (_down ? 1 : -1) : null;

  /// Ends the drag if [e] is its pointer; returns whether it was.
  bool end(PointerEvent e) {
    if (e.pointer != _pointer) return false;
    _pointer = null;
    return true;
  }
}
