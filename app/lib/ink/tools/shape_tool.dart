import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../../core/clock.dart';
import '../../domain/stroke.dart';
import '../input/live_ink.dart';
import '../shapes/shape_builder.dart';
import '../surface_model.dart';
import '../tool_settings.dart';
import '../viewport.dart';
import 'pointer_tool.dart';

/// Draws the selected [ShapeKind] by dragging out its bounding box (or,
/// for lines and arrows, from end to end), with the current pen's colour,
/// width and opacity. Holding Shift keeps proportions (squares, circles)
/// or snaps lines to 15° steps.
class ShapeTool implements PointerTool {
  ShapeTool({
    required this.model,
    required this.live,
    required this.tools,
    required this.viewport,
    this.clock = const Clock(),
  });

  final SurfaceModel Function() model;
  final LiveInk live;
  final ToolSettings tools;
  final ViewportController viewport;
  final Clock clock;

  /// Drags shorter than this (screen pixels) draw nothing.
  static const double minDrag = 4;

  Offset? _start;

  /// When the drag began (epoch ms): the shape's `createdAt`.
  int _startedAt = 0;
  Offset? _startScreen;
  bool _dragged = false;

  @override
  void down(ToolPointer p) {
    _start = p.world;
    _startedAt = clock.nowMs();
    _startScreen = p.screen;
    _dragged = false;
    const ink = InkTool.ballpoint;
    final config = tools.configOf(ink);
    live.begin(
      tool: ink,
      color: config.color,
      width: config.width,
      style: ShapeBuilder.styleFor(tools.styleFor(ink)),
    );
  }

  @override
  void move(ToolPointer p) {
    final start = _start;
    if (start == null) return;
    if (!_dragged && (p.screen - _startScreen!).distance < minDrag) return;
    _dragged = true;
    final kind = tools.shape;
    final end = HardwareKeyboard.instance.isShiftPressed
        ? constrain(kind, start, p.world)
        : p.world;
    live.replaceAll(
      ShapeBuilder.points(ShapeBuilder.outline(kind, start, end), spacing: 2 / viewport.scale),
    );
  }

  @override
  void up() {
    final points = live.finish();
    if (_dragged && points.length > 1) {
      final m = model();
      m.addStroke(
        Stroke(
          id: clock.newId(),
          surfaceId: m.surfaceId,
          tool: live.tool,
          color: live.color,
          width: live.width,
          style: live.style,
          points: points,
          createdAt: _startedAt,
        ),
      );
    }
    _start = null;
  }

  @override
  void cancel() {
    if (_start != null) live.finish();
    _start = null;
  }

  /// Square boxes for closed shapes; 15° angle steps for lines and arrows.
  static Offset constrain(ShapeKind kind, Offset start, Offset end) {
    final d = end - start;
    if (kind.isClosed) {
      final side = math.max(d.dx.abs(), d.dy.abs());
      return start + Offset(side * (d.dx < 0 ? -1 : 1), side * (d.dy < 0 ? -1 : 1));
    }
    const step = math.pi / 12;
    final angle = (d.direction / step).round() * step;
    return start + Offset.fromDirection(angle, d.distance);
  }
}
