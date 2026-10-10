import 'dart:async';

import 'package:flutter/services.dart';

import '../../domain/stroke.dart';
import '../geometry/straighten.dart';
import 'live_ink.dart';

/// "Hold to straighten": when the pen rests for [holdDuration] at the end
/// of a live stroke, the stroke snaps to a straight line; moving on then
/// moves the line's end. Only the straight line is ever committed, so a
/// single undo removes it.
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
  double _pressure = 0.5;
  double _scale = 1;

  /// Whether the live stroke has been straightened.
  bool get active => _from != null;

  /// A stroke started at [screen]; [enabled] reflects the user setting.
  void begin(Offset screen, {required bool enabled, required double scale}) {
    end();
    _scale = scale;
    if (enabled) _restart(screen);
  }

  /// The pen moved to [screen] / [point]. Returns true if the move was
  /// consumed (the stroke is straight and its end now follows the pen);
  /// otherwise the caller adds [point] to the live stroke as usual.
  bool move(Offset screen, StrokePoint point) {
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
    _from = points.first;
    _pressure = Straighten.medianPressure(points);
    live
      ..straightened = true
      ..replaceAll(Straighten.line(points, spacing: 2 / _scale));
    unawaited(HapticFeedback.selectionClick());
  }
}
