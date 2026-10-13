import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/chrome_fade.dart';
import '../../../ui/floating_panel.dart';
import '../toolbar/toolbar_metrics.dart';
import 'chrome_metrics.dart';
import 'puck_clearance.dart';

/// Hosts the floating toolbar where the user dragged it by its grip
/// (REDESIGN §2.1). Released within [snapDistance] of an edge, it snaps to
/// the middle of that edge: across the top or bottom, or running down the
/// left or right side ([ToolbarAxis] vertical). Fills the editor; only the
/// palette takes input.
class ToolbarSlot extends StatefulWidget {
  const ToolbarSlot({
    super.key,
    required this.toolbar,
    required this.insets,
    this.floatAt,
    this.onFloatMoved,
    this.visible = true,
    this.blocked,
  });

  final Widget toolbar;

  /// Whether something the palette must not cover lies under a rectangle
  /// (in this slot's coordinates, which are the editor's). Released over
  /// it, the palette moves to the nearest clear spot along the edges
  /// ([PuckClearance]): focus mode's puck stays clear of the writing.
  final bool Function(Rect rect)? blocked;

  /// Space taken by other chrome (top bar, safe areas) that the toolbar
  /// must stay clear of.
  final EdgeInsets insets;

  /// Position as fractions (0..1) of the free area.
  final (double, double)? floatAt;

  /// Called when a drag of the toolbar ends.
  final ValueChanged<(double, double)>? onFloatMoved;

  /// False in focus mode: the toolbar fades out and ignores input.
  final bool visible;

  /// How close to an edge (logical pixels) a released palette snaps to it.
  static const double snapDistance = 48;

  /// Where a palette released at [at] (fractions of the free area, which
  /// is [free] pixels: the room the palette can move in) ends up: the
  /// middle of the nearest edge within [snapDistance], else [at].
  static (double, double) snap((double, double) at, Size free) {
    final (x, y) = at;
    final distances = <(double, double), double>{
      (0, 0.5): x * free.width,
      (1, 0.5): (1 - x) * free.width,
      (0.5, 0): y * free.height,
      (0.5, 1): (1 - y) * free.height,
    };
    final nearest = distances.entries.reduce((a, b) => a.value <= b.value ? a : b);
    return nearest.value <= snapDistance ? nearest.key : at;
  }

  /// Whether a palette at [at] runs down a side edge.
  static bool isVertical((double, double)? at) => at != null && (at.$1 == 0 || at.$1 == 1);

  @override
  State<ToolbarSlot> createState() => _ToolbarSlotState();
}

class _ToolbarSlotState extends State<ToolbarSlot> {
  /// Position while dragging, as an [Alignment] within the free area.
  Alignment? _dragging;
  final GlobalKey _panel = GlobalKey();

  Alignment get _alignment => _dragging ?? _floatAlignment;

  Alignment get _floatAlignment {
    final (x, y) = widget.floatAt ?? (0.5, 0.82);
    return Alignment(x * 2 - 1, y * 2 - 1);
  }

  /// The room the palette can move in within [area].
  Size _free(Size area) {
    final child = _panel.currentContext?.size ?? Size.zero;
    return Size(
      (area.width - child.width).clamp(1, double.infinity),
      (area.height - child.height).clamp(1, double.infinity),
    );
  }

  Size _area = Size.zero;

  void _drag(DragUpdateDetails d, Size area) {
    _area = area;
    final free = _free(area);
    final current = _dragging ?? _floatAlignment;
    setState(() {
      _dragging = Alignment(
        (current.x + d.delta.dx * 2 / free.width).clamp(-1, 1),
        (current.y + d.delta.dy * 2 / free.height).clamp(-1, 1),
      );
    });
  }

  void _endDrag() {
    final a = _dragging;
    if (a == null) return;
    var at = ToolbarSlot.snap(((a.x + 1) / 2, (a.y + 1) / 2), _free(_area));
    if (widget.blocked case final blocked?) {
      at = PuckClearance.settle(at, rectAt: _rectAt, blocked: blocked);
    }
    widget.onFloatMoved?.call(at);
    setState(() => _dragging = null);
  }

  /// The palette's rectangle at [at] (fractions of the free area), in this
  /// slot's coordinates; turned to run down a side, it turns its size.
  Rect _rectAt((double, double) at) {
    var size = _panel.currentContext?.size ?? Size.zero;
    if (ToolbarSlot.isVertical(at) != ToolbarSlot.isVertical(widget.floatAt)) {
      size = size.flipped;
    }
    final padding = widget.insets + const EdgeInsets.all(ChromeMetrics.edge);
    final free = Size(
      math.max(0, _area.width - size.width),
      math.max(0, _area.height - size.height),
    );
    return Offset(padding.left + free.width * at.$1, padding.top + free.height * at.$2) & size;
  }

  @override
  Widget build(BuildContext context) {
    final padding = widget.insets + const EdgeInsets.all(ChromeMetrics.edge);
    // The axis changes only when a drag ends (never mid-drag).
    final axis = ToolbarSlot.isVertical(widget.floatAt) ? Axis.vertical : Axis.horizontal;
    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) => AnimatedAlign(
          alignment: _alignment,
          duration: _dragging != null ? Duration.zero : Motion.slow,
          curve: Motion.emphasized,
          child: ChromeFade(
            visible: widget.visible,
            edge: const Offset(0, 1),
            child: IgnorePointer(
              ignoring: !widget.visible,
              child: ConstrainedBox(
                key: _panel,
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth,
                  maxHeight: constraints.maxHeight,
                ),
                child: ToolbarAxis(axis: axis, child: _capsule(axis, constraints.biggest)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The palette: one raised panel (DESIGN §6.2) with the grip leading
  /// the bare [ToolbarSlot.toolbar].
  Widget _capsule(Axis axis, Size area) {
    final horizontal = axis == Axis.horizontal;
    return FloatingPanel(
      // The grip is the leading edge's padding.
      padding: horizontal
          ? const EdgeInsets.fromLTRB(0, Gaps.xs, Gaps.xs + Gaps.xxs, Gaps.xs)
          : const EdgeInsets.fromLTRB(Gaps.xs, 0, Gaps.xs, Gaps.xs + Gaps.xxs),
      child: Flex(
        direction: axis,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Grip(axis: axis, onDrag: (d) => _drag(d, area), onEnd: _endDrag),
          Flexible(child: widget.toolbar),
        ],
      ),
    );
  }
}

/// The handle by which the floating palette is dragged: two Graphite ticks
/// across its leading edge, like the marks on a ruler.
class _Grip extends StatelessWidget {
  const _Grip({required this.axis, required this.onDrag, required this.onEnd});

  /// The palette's axis: the grip leads it.
  final Axis axis;
  final GestureDragUpdateCallback onDrag;
  final VoidCallback onEnd;

  /// The grip's extent along the palette.
  static const double extent = 24;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    final horizontal = axis == Axis.horizontal;
    Widget tick() => Container(
      width: horizontal ? Hairline.width : Gaps.md,
      height: horizontal ? Gaps.md : Hairline.width,
      color: color,
    );
    return Tooltip(
      message: 'Drag to move the toolbar',
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: onDrag,
          onPanEnd: (_) => onEnd(),
          onPanCancel: onEnd,
          child: SizedBox(
            // Across, as deep as the tools beside it: the whole edge takes
            // the drag.
            width: horizontal ? extent : Targets.barHit(context),
            height: horizontal ? Targets.barHit(context) : extent,
            child: Flex(
              direction: axis,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                tick(),
                SizedBox.square(dimension: Gaps.xs - Hairline.width),
                tick(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
