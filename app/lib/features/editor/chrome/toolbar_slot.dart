import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

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
    this.joined = false,
    this.blocked,
  });

  final Widget toolbar;

  /// Whether something the palette must not cover lies under a rectangle
  /// (in this slot's coordinates, which are the editor's). Released over
  /// it, the palette moves to the nearest clear spot along the edges
  /// ([PuckClearance]): focus mode's puck stays clear of the writing.
  final bool Function(Rect rect)? blocked;

  /// Whether [toolbar] is bare and shares one capsule with the grip (focus
  /// mode's puck), instead of a panel of its own beside the grip's.
  final bool joined;

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

  /// The grip and the toolbar: side by side, or in one capsule if [joined].
  Widget _capsule(Axis axis, Size area) {
    final grip = _Grip(
      axis: axis,
      framed: !widget.joined,
      onDrag: (d) => _drag(d, area),
      onEnd: _endDrag,
    );
    final row = Flex(
      direction: axis,
      mainAxisSize: MainAxisSize.min,
      children: [
        grip,
        SizedBox(
          width: axis == Axis.horizontal && !widget.joined ? Gaps.xs : 0,
          height: axis == Axis.vertical && !widget.joined ? Gaps.xs : 0,
        ),
        Flexible(child: widget.toolbar),
      ],
    );
    if (!widget.joined) return row;
    return FloatingPanel(radius: Radii.pill, padding: const EdgeInsets.all(Gaps.xs), child: row);
  }
}

/// The handle by which the floating toolbar is dragged.
class _Grip extends StatelessWidget {
  const _Grip({
    required this.axis,
    required this.framed,
    required this.onDrag,
    required this.onEnd,
  });

  /// Whether the grip is a capsule of its own (else it sits in the
  /// toolbar's).
  final bool framed;

  /// The palette's axis: the grip leads it.
  final Axis axis;
  final GestureDragUpdateCallback onDrag;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Framed it stands 48 high on its own; inside a capsule it takes the
    // capsule's height.
    final handle = SizedBox(
      width: axis == Axis.horizontal ? 28 : (framed ? 48 : null),
      height: axis == Axis.horizontal ? (framed ? 48 : null) : 28,
      child: Icon(
        axis == Axis.horizontal ? Symbols.drag_indicator_sharp : Symbols.drag_handle_sharp,
        size: Glyphs.bar,
        color: scheme.onSurfaceVariant,
      ),
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
          child: framed
              ? FloatingPanel(radius: Radii.pill, padding: EdgeInsets.zero, child: handle)
              : handle,
        ),
      ),
    );
  }
}
