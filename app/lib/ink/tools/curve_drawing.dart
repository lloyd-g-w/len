import 'dart:ui';

import '../../core/clock.dart';
import '../../domain/stroke.dart';
import '../input/live_ink.dart';
import '../selection/selection_chrome.dart';
import '../shapes/shape_builder.dart';
import '../surface_model.dart';
import '../viewport.dart';
import 'pointer_tool.dart';

/// The Shape tool drawing a curve, a gesture at a time: a tap places an
/// anchor (a corner: straight on to the next), a press-drag places one and
/// pulls its tangents out symmetrically (smooth), a tap on the first anchor
/// closes the curve (a drag there pulls its tangents too) and finishes it,
/// a double tap (a second tap on the last anchor) finishes it open, as do
/// Enter and a change of tool ([finish]); Escape drops it ([cancel]). The
/// curve so far is the live stroke between gestures; it is committed as
/// one stroke (one undo step), closed ones with the [fill] given at the
/// start.
class CurveDrawing {
  CurveDrawing({required this.live, required this.viewport, this.clock = const Clock()});

  final LiveInk live;
  final ViewportController viewport;
  final Clock clock;

  /// Taps closer together than this (ms) on the last anchor finish.
  static const int doubleTapMs = 400;

  /// Movement (screen pixels) that turns a press into a tangent pull.
  static const double slop = 4;

  SurfaceModel? _model;
  int? _fill;
  int _startedAt = 0;

  /// The open spline so far: anchor, out, in, anchor, … (the last anchor's
  /// out handle is [_lastOut], the first one's in handle [_firstIn]).
  List<Offset> _points = [];
  Offset _lastOut = Offset.zero;
  Offset? _firstIn;

  /// The state before the gesture in progress, to go back to if it is
  /// abandoned.
  ({List<Offset> points, Offset lastOut, Offset? firstIn})? _before;

  Offset _pressScreen = Offset.zero;
  bool _dragged = false;
  bool _closing = false;
  bool _finishing = false;
  int _lastUp = -doubleTapMs - 1;
  bool _pressed = false;

  /// Whether a curve is being drawn.
  bool get active => _model != null;

  int get _anchors => (_points.length + 2) ~/ 3;

  /// A press at [p]: the first anchor of a new curve on [model] (whose
  /// live stroke [begin] starts), or the next one, closing or finishing.
  void down(
    ToolPointer p, {
    required SurfaceModel model,
    required void Function() begin,
    int? fill,
  }) {
    _pressed = true;
    _pressScreen = p.screen;
    _dragged = false;
    _closing = _finishing = false;
    if (!active) {
      _model = model;
      _fill = fill;
      _startedAt = clock.nowMs();
      begin();
      _before = null;
      _points = [p.world];
      _lastOut = p.world;
      _firstIn = null;
      _show();
      return;
    }
    _before = (points: [..._points], lastOut: _lastOut, firstIn: _firstIn);
    final reach = SelectionChrome.shapeHitRadius(p.kind);
    final last = viewport.toScreen(_points.last), first = viewport.toScreen(_points.first);
    if ((p.screen - last).distance <= reach && clock.nowMs() - _lastUp <= doubleTapMs) {
      _finishing = true;
      return;
    }
    if (_anchors >= 2 && (p.screen - first).distance <= reach) {
      _closing = true;
      _show();
      return;
    }
    _points = [..._points, _lastOut, p.world, p.world];
    _lastOut = p.world;
    _show();
  }

  /// The pointer at [p]: after the slop, the anchor pressed gets tangents
  /// pulled out to [p] (and opposite).
  void move(ToolPointer p) {
    if (!_pressed || !active || _finishing) return;
    if (!_dragged && (p.screen - _pressScreen).distance < slop) return;
    _dragged = true;
    final q = p.world;
    if (_closing) {
      final a = _points.first;
      _points = [..._points]..[1] = q;
      _firstIn = a * 2 - q;
    } else {
      final i = _points.length - 1, a = _points[i];
      _lastOut = q;
      if (i == 0) {
        _firstIn = a * 2 - q;
      } else {
        _points = [..._points]..[i - 1] = a * 2 - q;
      }
    }
    _show();
  }

  /// The pointer lifted: a closing press closes and finishes the curve, a
  /// finishing one finishes it.
  void up() {
    if (!_pressed) return;
    _pressed = false;
    _lastUp = _dragged ? -doubleTapMs - 1 : clock.nowMs();
    if (_closing) {
      _commit(closed: true);
    } else if (_finishing) {
      _commit(closed: false);
    }
  }

  /// The gesture was abandoned (it became a pinch): the curve is as it was
  /// before it, or none if it was the first.
  void cancelGesture() {
    if (!_pressed) return;
    _pressed = false;
    final before = _before;
    if (before == null) {
      cancel();
      return;
    }
    _points = before.points;
    _lastOut = before.lastOut;
    _firstIn = before.firstIn;
    _show();
  }

  /// Commits the curve drawn so far (open); false when none was drawn.
  bool finish() {
    if (!active) return false;
    _commit(closed: false);
    return true;
  }

  /// Drops the curve drawn so far; false when none was drawn.
  bool cancel() {
    if (!active) return false;
    live.finish();
    _model = null;
    _pressed = false;
    return true;
  }

  /// The curve as drawn so far, closed or not; null with one anchor.
  ShapeGeometry? _geometry({required bool closed}) {
    if (_anchors < 2) return null;
    if (!closed) return ShapeGeometry(ShapeKind.curve, _points);
    return ShapeGeometry(ShapeKind.curve, [..._points, _lastOut, _firstIn ?? _points.first]);
  }

  void _show() {
    final shape = live.shape = _geometry(closed: _closing);
    final spacing = 2 / viewport.scale;
    live.replaceAll(
      shape == null
          ? [StrokePoint(_points.first.dx, _points.first.dy, 0.5)]
          : ShapeBuilder.pointsOf(shape, spacing: spacing),
    );
  }

  void _commit({required bool closed}) {
    final model = _model!;
    final shape = _geometry(closed: closed);
    if (shape != null) live.shape = shape;
    final style = closed ? live.style.withFill(_fill) : live.style;
    final points = shape == null
        ? const <StrokePoint>[]
        : ShapeBuilder.pointsOf(shape, spacing: 2 / viewport.scale);
    final tool = live.tool, color = live.color, width = live.width;
    live.finish();
    _model = null;
    if (shape == null || _tiny(shape)) return;
    model.addStroke(
      Stroke(
        id: clock.newId(),
        surfaceId: model.surfaceId,
        tool: tool,
        color: color,
        width: width,
        style: style,
        points: points,
        createdAt: _startedAt,
        shape: shape,
      ),
    );
  }

  /// Whether [shape] spans less than a few pixels (taps on one spot).
  bool _tiny(ShapeGeometry shape) {
    var r = Rect.fromPoints(shape.points.first, shape.points.first);
    for (final p in shape.points) {
      r = r.expandToInclude(Rect.fromPoints(p, p));
    }
    return r.longestSide * viewport.scale < slop;
  }
}
