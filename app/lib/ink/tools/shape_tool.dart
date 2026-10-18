import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../../core/clock.dart';
import '../../domain/stroke.dart';
import '../input/live_ink.dart';
import '../selection/connectors.dart';
import '../selection/selection_controller.dart';
import '../shapes/shape_builder.dart';
import '../shapes/shape_snap.dart';
import '../surface_model.dart';
import '../tool_settings.dart';
import '../viewport.dart';
import 'content_hit_test.dart';
import 'curve_drawing.dart';
import 'lasso_tool.dart';
import 'pointer_tool.dart';

/// Draws the selected [ShapeKind] by dragging out its bounding box (or,
/// for lines and arrows, from end to end), with the current pen's colour,
/// width and opacity; closed shapes get [ToolSettings.shapeFill]. The
/// preview is always the shape from the press to the pointer, and the
/// shape committed is the one last shown. Without Shift, nearly regular
/// shapes and nearly level, upright or diagonal lines snap ([ShapeSnap]);
/// holding Shift (pressed or released at any time during the drag) makes
/// the shape regular (squares, circles, equilateral triangles, regular
/// stars) or steps lines by 15°. A tap on a shape selects it, to edit its
/// points. Curves are drawn anchor by anchor ([CurveDrawing]): [finishCurve]
/// (Enter, another tool) commits one, [cancelCurve] (Escape) drops it. With
/// Curve picked, a tap on a shape selects it too unless a curve is being
/// drawn (then it places an anchor there); a drag from a shape starts a
/// curve.
class ShapeTool implements PointerTool {
  ShapeTool({
    required this.model,
    required this.live,
    required this.tools,
    required this.viewport,
    this.selection,
    this.clock = const Clock(),
  });

  final SurfaceModel Function() model;
  final LiveInk live;
  final ToolSettings tools;
  final ViewportController viewport;

  /// Where a tap on a shape selects it.
  final SelectionController? selection;
  final Clock clock;

  /// Drags shorter than this (screen pixels) draw nothing.
  static const double minDrag = 4;

  Offset? _start;
  Offset _end = Offset.zero;

  /// When the drag began (epoch ms): the shape's `createdAt`.
  int _startedAt = 0;
  Offset _startScreen = Offset.zero;
  bool _dragged = false;
  ShapeGeometry? _shape;

  /// A press on a shape with Curve picked and none being drawn: a tap
  /// selects the shape, a drag starts a curve from here.
  ToolPointer? _onShape;

  /// The curve being drawn, anchor by anchor.
  late final CurveDrawing curve = CurveDrawing(live: live, viewport: viewport, clock: clock);

  /// Commits the curve being drawn (Enter, a change of tool); false when
  /// none is.
  bool finishCurve() => curve.finish();

  /// Drops the curve being drawn (Escape); false when none is.
  bool cancelCurve() => curve.cancel();

  @override
  void down(ToolPointer p) {
    if (tools.shape == ShapeKind.curve) {
      _onShape = null;
      if (!curve.active && _shapeAt(p.world) != null) {
        _onShape = p;
        return;
      }
      _curveDown(p);
      return;
    }
    curve.finish();
    _start = _end = p.world;
    _startedAt = clock.nowMs();
    _startScreen = p.screen;
    _dragged = false;
    _shape = null;
    _begin(tools.shape);
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  void _curveDown(ToolPointer p) {
    final config = tools.configOf(InkTool.ballpoint);
    curve.down(
      p,
      model: model(),
      fill: tools.shapeFill.colorFor(config.color),
      begin: () => _begin(ShapeKind.curve),
    );
  }

  /// Starts the live stroke of a [kind] with the pen's look.
  void _begin(ShapeKind kind) {
    const ink = InkTool.ballpoint;
    final config = tools.configOf(ink);
    final style = ShapeBuilder.styleFor(tools.styleFor(ink).copyWith(unit: 1 / viewport.scale));
    live
      ..begin(
        tool: ink,
        color: config.color,
        width: config.width,
        // Closed shapes take the tool's fill (curves once closed).
        style: kind.isClosed ? style.withFill(tools.shapeFill.colorFor(config.color)) : style,
      )
      // Not free-hand ink (no low-latency overlay).
      ..straightened = true;
  }

  @override
  void move(ToolPointer p) {
    if (_onShape case final press?) {
      if ((p.screen - press.screen).distance < CurveDrawing.slop) return;
      _onShape = null;
      _curveDown(press);
    }
    if (curve.active) return curve.move(p);
    if (_start == null) return;
    _end = p.world;
    if (!_dragged && (p.screen - _startScreen).distance < minDrag) return;
    _dragged = true;
    _show();
  }

  /// Shift pressed or released mid-drag: the preview follows at once.
  bool _onKey(KeyEvent event) {
    final key = event.logicalKey;
    final shift = key == LogicalKeyboardKey.shiftLeft || key == LogicalKeyboardKey.shiftRight;
    if (shift && _dragged && _start != null) _show();
    return false;
  }

  void _show() {
    final start = _start!;
    final kind = tools.shape;
    final end = HardwareKeyboard.instance.isShiftPressed
        ? constrain(kind, start, _end)
        : ShapeSnap.dragEnd(kind, start, _end);
    final shape = live.shape = _shape = kind == ShapeKind.line || kind == ShapeKind.arrow
        ? _connected(kind, start, end)
        : ShapeBuilder.dragged(kind, start, end);
    live.replaceAll(ShapeBuilder.pointsOf(shape, spacing: 2 / viewport.scale));
  }

  /// The line or arrow from [start] to [end], its ends attached to the
  /// shapes they start or end on (or in), shown with the selection's
  /// chrome ([Connectors]). The tip's target is looked for at [end], the
  /// Shift- or snap-adjusted end, not the pointer: the end drawn is the
  /// one that attaches (UX_AUDIT R25-31).
  ShapeGeometry _connected(ShapeKind kind, Offset start, Offset end) {
    final m = model(), reach = LassoTool.attachReach / viewport.scale;
    final from = Connectors.find(m, start, reach: reach, towards: end);
    final to = Connectors.find(m, end, reach: reach, towards: start);
    selection?.attachHint = to ?? from;
    return ShapeGeometry(
      kind,
      [from?.point ?? start, to?.point ?? end],
      tail: from?.attachment,
      tip: to?.attachment,
    );
  }

  @override
  void up() {
    if (_onShape case final press?) {
      _onShape = null;
      curve.forget();
      return _tap(press.world);
    }
    if (curve.active) return curve.up();
    _stopKeys();
    selection?.attachHint = null;
    final shape = _shape;
    final points = live.finish();
    if (_dragged && shape != null && points.length > 1) {
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
          shape: shape,
        ),
      );
    } else if (!_dragged && _start != null) {
      _tap(_start!);
    }
    _start = null;
    _shape = null;
  }

  @override
  void cancel() {
    _onShape = null;
    if (curve.active) return curve.cancelGesture();
    _stopKeys();
    selection?.attachHint = null;
    if (_start != null) live.finish();
    _start = null;
    _shape = null;
  }

  void _stopKeys() => HardwareKeyboard.instance.removeHandler(_onKey);

  /// A tap on a shape selects it (its points become handles).
  void _tap(Offset world) {
    if (_shapeAt(world) case final hit?) selection!.select([hit], const []);
  }

  /// The shape a tap at [world] selects, if any (none without a [selection]).
  Stroke? _shapeAt(Offset world) {
    if (selection == null) return null;
    final hit = ContentHitTest.strokeAt(model(), world, 8 / viewport.scale);
    return hit?.shape == null ? null : hit;
  }

  /// Boxes making closed shapes regular (squares, circles, equilateral
  /// triangles, regular stars: [ShapeBuilder.regularAspect]) as large as
  /// the drag; 15° angle steps for lines and arrows.
  static Offset constrain(ShapeKind kind, Offset start, Offset end) {
    final d = end - start;
    if (kind.isClosed) {
      final aspect = ShapeBuilder.regularAspect(kind);
      final height = math.max(d.dx.abs() / aspect, d.dy.abs());
      return start + Offset(height * aspect * (d.dx < 0 ? -1 : 1), height * (d.dy < 0 ? -1 : 1));
    }
    const step = math.pi / 12;
    final angle = (d.direction / step).round() * step;
    return start + Offset.fromDirection(angle, d.distance);
  }
}
