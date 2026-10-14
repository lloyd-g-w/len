import 'dart:async';

import 'package:flutter/services.dart';

import '../../domain/stroke.dart';
import '../geometry/straighten.dart';
import '../shapes/polyline.dart';
import '../shapes/shape_builder.dart';
import '../shapes/shape_recognizer.dart';
import 'live_ink.dart';

/// "Hold to snap": when the pen rests for [holdDuration] at the end of a
/// live stroke, the stroke is recognised ([ShapeRecognizer]) and replaced,
/// in place, by a clean shape with editable geometry ([LiveInk.shape]):
///  * a nearly straight open stroke becomes a line — moving on then moves
///    the line's end — and one ending in a head an arrow;
///  * a closed stroke at least [minShape] across becomes a clean
///    rectangle, ellipse, triangle, diamond or polygon (which then stays
///    put until the pen lifts);
///  * anything else (handwriting, a curve, a scribble, a small letter "o")
///    is left alone.
/// Only the clean shape is ever committed, so a single undo removes it.
///
/// An ink with [PenConfig.straight] is straight from the start: [begin]
/// with `straight` makes the live stroke the line from pen-down to the pen.
class HoldToStraighten {
  HoldToStraighten(this.live);

  final LiveInk live;

  /// How long the pen must rest to straighten the stroke.
  static const Duration holdDuration = Duration(milliseconds: 600);

  /// Movement (screen pixels) still counted as "holding still".
  static const double holdTolerance = 4;

  /// Strokes shorter than this (screen pixels) are never straightened.
  static const double minLength = 24;

  /// Closed strokes smaller than this (screen pixels, their longest side)
  /// stay as written: letters and digits ("o", "0", "8").
  static const double minShape = 48;

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

  Timer? _timer;
  Offset? _anchor;
  StrokePoint? _from;
  bool _shaped = false;
  double _pressure = 0.5;
  double _scale = 1;

  /// Whether the live stroke has been straightened.
  bool get active => _from != null || _shaped;

  /// A stroke started at [screen]; [enabled] reflects the user setting.
  /// With [straight], the live stroke (its first point already added) is a
  /// straight line from that point to the pen until it lifts.
  void begin(Offset screen, {required bool enabled, required double scale, bool straight = false}) {
    end();
    _scale = scale;
    if (straight) {
      final from = live.points.first;
      _from = from;
      _pressure = from.pressure;
      live.straightened = true;
    } else if (enabled) {
      _restart(screen);
    }
  }

  /// The pen moved to [screen] / [point]. Returns true if the move was
  /// consumed (the stroke is straight and its end now follows the pen);
  /// otherwise the caller adds [point] to the live stroke as usual.
  bool move(Offset screen, StrokePoint point) {
    if (_shaped) return true;
    final from = _from;
    if (from != null) {
      live
        ..shape = ShapeGeometry(ShapeKind.line, [from.offset, point.offset])
        ..replaceAll(
          Straighten.line([from, StrokePoint(point.x, point.y, _pressure)], spacing: 2 / _scale),
        );
      return true;
    }
    final anchor = _anchor;
    if (anchor != null && (screen - anchor).distance > holdTolerance) _restart(screen);
    return false;
  }

  /// The stroke ended or was abandoned.
  void end() {
    _timer?.cancel();
    _timer = null;
    _anchor = null;
    _from = null;
    _shaped = false;
  }

  void _restart(Offset screen) {
    _timer?.cancel();
    _anchor = screen;
    _timer = Timer(holdDuration, _snap);
  }

  void _snap() {
    _timer = null;
    final points = live.points;
    if (!live.isDrawing || Straighten.pathLength(points) * _scale < minLength) return;
    final offsets = [for (final p in points) p.offset];
    final shape = ShapeRecognizer.recognize(offsets);
    if (shape == null) return;
    if (shape.kind.isClosed && Polyline.bounds(offsets).longestSide * _scale < minShape) return;
    _pressure = Straighten.medianPressure(points);
    live
      ..straightened = true
      ..style = ShapeBuilder.styleFor(live.style)
      ..shape = shape;
    if (shape.kind == ShapeKind.line) {
      _from = points.first;
      live.replaceAll(Straighten.line(points, spacing: 2 / _scale));
    } else {
      _shaped = true;
      live.replaceAll(ShapeBuilder.pointsOf(shape, spacing: 2 / _scale, pressure: _pressure));
    }
    unawaited(HapticFeedback.selectionClick());
  }
}
