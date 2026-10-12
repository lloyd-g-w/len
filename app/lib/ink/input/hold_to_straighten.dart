import 'dart:async';

import 'package:flutter/services.dart';

import '../../domain/stroke.dart';
import '../geometry/straighten.dart';
import '../shapes/shape_builder.dart';
import '../shapes/shape_kind.dart';
import '../shapes/shape_recognizer.dart';
import 'live_ink.dart';

/// "Hold to snap": when the pen rests for [holdDuration] at the end of a
/// live stroke, the stroke is recognised ([ShapeRecognizer]) and replaced:
///  * an open stroke becomes a straight line — moving on then moves the
///    line's end — or an arrow;
///  * a closed stroke becomes a clean rectangle, ellipse, triangle or
///    polygon (which then stays put until the pen lifts);
///  * an unrecognisable closed stroke (a scribble) is left alone.
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
      live.replaceAll(
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
    final shape = ShapeRecognizer.recognize([for (final p in points) p.offset]);
    if (shape == null) return;
    _pressure = Straighten.medianPressure(points);
    if (shape.kind == ShapeKind.line) {
      _from = points.first;
      live
        ..straightened = true
        ..replaceAll(Straighten.line(points, spacing: 2 / _scale));
    } else {
      _shaped = true;
      live
        ..straightened = true
        ..style = ShapeBuilder.styleFor(live.style)
        ..replaceAll(ShapeBuilder.points(shape.outline, spacing: 2 / _scale, pressure: _pressure));
    }
    unawaited(HapticFeedback.selectionClick());
  }
}
