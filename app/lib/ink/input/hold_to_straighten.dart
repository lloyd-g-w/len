import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../../domain/stroke.dart';
import '../geometry/straighten.dart';
import '../shapes/curve_recognizer.dart';
import '../shapes/held_shape.dart';
import '../shapes/polyline.dart';
import '../shapes/shape_builder.dart';
import '../shapes/shape_recognizer.dart';
import '../shapes/shape_snap.dart';
import 'live_ink.dart';

/// "Hold to snap": when the pen rests for [holdDuration] at the end of a
/// live stroke, the stroke is recognised ([ShapeRecognizer]) and replaced,
/// in place, by a clean shape with editable geometry ([LiveInk.shape]):
///  * a nearly straight open stroke becomes a line — moving on then moves
///    the line's end — and one ending in a head an arrow; both snap level,
///    upright or diagonal when nearly so ([ShapeSnap.lineEnd]);
///  * a closed stroke at least [minShape] across becomes a clean
///    rectangle, circle, ellipse, triangle, diamond or polygon;
///  * a smooth stroke that is none of those, at least [minCurve] across,
///    becomes a curve (a fitted spline, [CurveRecognizer]);
///  * until the pen lifts, moving it on transforms the snapped shape
///    ([HeldShape]): an arrow's tip follows it, anything else turns and
///    scales about its centre with it (once it has moved [holdTolerance]
///    from where it snapped);
///  * anything else (handwriting, a scribble, a small letter "o") is left
///    alone.
/// Only the clean shape is ever committed, so a single undo removes it.
///
/// An ink with [PenConfig.straight] is straight from the start: [begin]
/// with `straight` makes the live stroke the line from pen-down to the pen.
class HoldToStraighten {
  HoldToStraighten(this.live);

  final LiveInk live;

  /// Called when the hold is up, before the stroke is read: input still
  /// held back (a mouse's levelling trail) is added to the live stroke.
  void Function()? beforeSnap;

  /// Whether [beforeSnap] is running (its points are the rest's, not a
  /// new movement restarting the hold).
  bool _flushing = false;

  /// How long the pen must rest to straighten the stroke.
  static const Duration holdDuration = Duration(milliseconds: 600);

  /// Movement (screen pixels) still counted as "holding still".
  static const double holdTolerance = 4;

  /// Strokes shorter than this (screen pixels) are never straightened.
  static const double minLength = 48;

  /// Closed strokes smaller than this (screen pixels, their longest side)
  /// stay as written: letters and digits ("o", "0", "8").
  static const double minShape = 48;

  /// Smooth strokes smaller than this (screen pixels, their longest side)
  /// stay as written rather than becoming a curve: letters ("c", "s").
  static const double minCurve = 128;

  /// The shortest open stroke (screen pixels) [wouldSnap] counts as a
  /// line someone might have wanted straight, and the smallest closed one.
  static const double hintLine = 120, hintShape = 48;

  /// Whether [points] (world, at [scale]) were drawn as a clean line or
  /// shape would be: a long, nearly straight stroke, or a closed one that
  /// is recognised as a shape. For teaching hold to snap, not for snapping.
  static bool wouldSnap(List<Offset> points, double scale) {
    if (points.length < 2) return false;
    final shape = ShapeRecognizer.recognize(points);
    if (shape == null) return false;
    final bounds = Polyline.bounds(points);
    if (shape.kind != ShapeKind.line) return bounds.longestSide * scale >= hintShape;
    final a = points.first, b = points.last, chord = b - a;
    final length = chord.distance;
    if (length * scale < hintLine) return false;
    // Nearly straight already: no point further than 4 % of it off the chord.
    for (final p in points) {
      final off = (chord.dx * (p.dy - a.dy) - chord.dy * (p.dx - a.dx)).abs() / length;
      if (off > 0.04 * length) return false;
    }
    return true;
  }

  /// What [points] (world, at [scale]) snap to when the pen rests at
  /// their end: the recognised shape, unless the stroke is too short or a
  /// closed one too small (a letter); failing that, a smooth stroke at
  /// least [minCurve] across becomes a curve ([CurveRecognizer]).
  static ShapeGeometry? snapOf(List<StrokePoint> points, double scale) {
    if (Straighten.pathLength(points) * scale < minLength) return null;
    final offsets = [for (final p in points) p.offset];
    final size = Polyline.bounds(offsets).longestSide * scale;
    final shape = ShapeRecognizer.recognize(offsets);
    if (shape == null) return size >= minCurve ? CurveRecognizer.recognize(offsets) : null;
    if (shape.kind.isClosed && size < minShape) return null;
    return shape;
  }

  Timer? _timer;

  /// Where the pen has been since it was last more than [holdTolerance]
  /// from where it is now: (screen position, time in ms, index of the
  /// live point). The first is where it came to rest: the hold counts
  /// from then, and what follows is the pen resting, not drawing.
  final List<(Offset, int, int)> _resting = [];
  StrokePoint? _from;
  bool _shaped = false;

  /// The shape snapped while the pen is down, which moving it transforms.
  HeldShape? _held;

  /// Where the pen was when the shape snapped (screen), and whether it has
  /// moved away from there since (the transform follows it then).
  Offset _heldAt = Offset.zero;
  bool _transforming = false;

  /// Where the pen is now (screen and world).
  Offset _penScreen = Offset.zero;
  Offset _penWorld = Offset.zero;
  double _pressure = 0.5;
  double _scale = 1;

  /// Whether the live stroke has been straightened.
  bool get active => _from != null || _shaped;

  /// A stroke started at [screen]; [enabled] reflects the user setting.
  /// With [straight], the live stroke (its first point already added) is a
  /// straight line from that point to the pen until it lifts.
  void begin(
    Offset screen, {
    required bool enabled,
    required double scale,
    bool straight = false,
    int timeMs = 0,
  }) {
    end();
    _scale = scale;
    _penScreen = screen;
    if (live.points.isNotEmpty) _penWorld = live.points.last.offset;
    if (straight) {
      final from = live.points.first;
      _from = from;
      _pressure = from.pressure;
      live.straightened = true;
    } else if (enabled) {
      _resting.add((screen, timeMs, live.points.length - 1));
      _timer = Timer(holdDuration, _snap);
    }
  }

  /// The pen moved to [screen] / [point] at [timeMs]. Returns true if the
  /// move was consumed (the stroke is straight and its end now follows the
  /// pen); otherwise the caller adds [point] to the live stroke as usual.
  bool move(Offset screen, StrokePoint point, {int timeMs = 0}) {
    _penScreen = screen;
    _penWorld = point.offset;
    if (_shaped) {
      _transform(screen, point.offset);
      return true;
    }
    final from = _from;
    if (from != null) {
      final end = ShapeSnap.lineEnd(from.offset, point.offset);
      live
        ..shape = ShapeGeometry(ShapeKind.line, [from.offset, end])
        ..replaceAll(
          Straighten.line([from, StrokePoint(end.dx, end.dy, _pressure)], spacing: 2 / _scale),
        );
      return true;
    }
    if (_resting.isNotEmpty) _rest(screen, timeMs);
    return false;
  }

  /// The stroke ended or was abandoned.
  void end() {
    _timer?.cancel();
    _timer = null;
    _resting.clear();
    _from = null;
    _shaped = false;
    _held = null;
    _transforming = false;
  }

  /// The pen moved on to [screen] / [world] after a shape snapped: the
  /// shape follows it ([HeldShape.at]).
  void _transform(Offset screen, Offset world) {
    final held = _held;
    if (held == null) return;
    if (!_transforming && (screen - _heldAt).distance <= holdTolerance) return;
    _transforming = true;
    final shape = held.at(world, minReach: minReach / _scale);
    if (shape == live.shape) return;
    live
      ..shape = shape
      ..replaceAll(ShapeBuilder.pointsOf(shape, spacing: 2 / _scale, pressure: _pressure));
  }

  /// How far (screen pixels) from a shape's centre the pen must have
  /// snapped it for moving on to turn and scale it.
  static const double minReach = 12;

  /// The pen is at [screen]: the rest starts after the last place it was
  /// farther than [holdTolerance] from here (a pen coming to rest still
  /// slows down, then drifts a pixel or so), and the hold counts from then.
  void _rest(Offset screen, int timeMs) {
    _resting.add((screen, timeMs, live.points.length)); // [live] adds it next.
    var from = _resting.length - 1;
    while (from > 0 && (_resting[from - 1].$1 - screen).distance <= holdTolerance) {
      from--;
    }
    if (from == 0) return;
    _resting.removeRange(0, from);
    if (_flushing) return;
    final held = timeMs - _resting.first.$2;
    _timer?.cancel();
    _timer = Timer(holdDuration - Duration(milliseconds: math.max(0, held)), _snap);
  }

  void _snap() {
    _timer = null;
    _flushing = true;
    try {
      beforeSnap?.call();
    } finally {
      _flushing = false;
    }
    final points = live.points;
    if (!live.isDrawing) return;
    // Recognised as drawn: a resting pen drifts by a pixel or so, which
    // would add a tangle at the end (a line's detour, an arrow's wings).
    final rest = _resting.isEmpty ? points.length - 1 : _resting.first.$3;
    final drawn = points.sublist(0, math.min(points.length, rest + 1));
    var shape = snapOf(drawn, _scale);
    if (shape == null) return;
    final first = points.first.offset;
    if (shape.kind == ShapeKind.line) {
      shape = ShapeGeometry(ShapeKind.line, [first, ShapeSnap.lineEnd(first, points.last.offset)]);
    } else if (shape.kind == ShapeKind.arrow) {
      final [tail, tip] = shape.points;
      shape = ShapeGeometry(ShapeKind.arrow, [tail, ShapeSnap.lineEnd(tail, tip)]);
    }
    _pressure = Straighten.medianPressure(points);
    live
      ..straightened = true
      ..style = ShapeBuilder.styleFor(live.style)
      ..shape = shape;
    if (shape.kind == ShapeKind.line) {
      _from = points.first;
      final end = shape.points[1];
      live.replaceAll(
        Straighten.line([...points, StrokePoint(end.dx, end.dy, _pressure)], spacing: 2 / _scale),
      );
    } else {
      _shaped = true;
      _held = HeldShape(shape, _penWorld);
      _heldAt = _penScreen;
      live.replaceAll(ShapeBuilder.pointsOf(shape, spacing: 2 / _scale, pressure: _pressure));
    }
    unawaited(HapticFeedback.selectionClick());
  }
}
