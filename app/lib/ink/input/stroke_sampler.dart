import 'package:flutter/gestures.dart';

import '../../domain/stroke.dart';
import '../viewport.dart';
import 'point_spacing.dart';
import 'pressure_filter.dart';
import 'stylus_buttons.dart';

/// Turns one stroke's raw pointer samples into stroke points: pressure
/// normalised and smoothed ([PressureFilter]), samples closer than
/// [PointSpacing.minDistance] thinned out (keeping a dropped cusp tip), and
/// the end settled.
class StrokeSampler {
  /// [onKeep] receives each kept point with its screen position, the
  /// screen position of the point before it and its time (whole ms).
  StrokeSampler(this.viewport, this.onKeep);

  final ViewportController viewport;
  final void Function(Offset from, Offset at, StrokePoint point, int timeMs) onKeep;

  /// Smooths stylus pressure and suppresses spikes at pen-up.
  final PressureFilter _pressure = PressureFilter();

  /// Points dropped since the last kept one (screen position, point, time).
  final List<(Offset, StrokePoint, int)> _dropped = [];

  /// Starts a new contact.
  void reset() {
    _pressure.reset();
    _dropped.clear();
  }

  /// The stroke's first point, at [e].
  StrokePoint first(PointerEvent e) {
    final world = viewport.toWorld(e.localPosition);
    final pressure = _pressure.next(pressureOf(e), synthesized: e.synthesized);
    return StrokePoint(world.dx, world.dy, pressure);
  }

  /// Samples [screen] at [timeMs] after the last kept point at [from];
  /// returns whether it was kept (then after any dropped point kept as a
  /// detail), each through [onKeep].
  bool add(Offset from, Offset screen, double pressure, int timeMs, {bool synthesized = false}) {
    final step = (screen - from).distance;
    final world = viewport.toWorld(screen);
    final point = StrokePoint(
      world.dx,
      world.dy,
      _pressure.next(pressure, synthesized: synthesized),
    );
    if (step < PointSpacing.minDistance) {
      _dropped.add((screen, point, timeMs));
      return false;
    }
    _keepExtremeDropped(from, screen);
    onKeep(from, screen, point, timeMs);
    return true;
  }

  /// Keeps the dropped point furthest from the line [from] → [to], if it
  /// is far enough off it to be a detail (a cusp tip).
  void _keepExtremeDropped(Offset from, Offset to) {
    if (_dropped.isEmpty) return;
    var best = PointSpacing.keepExtreme;
    (Offset, StrokePoint, int)? keep;
    for (final dropped in _dropped) {
      final d = _distanceToSegment(dropped.$1, from, to);
      if (d > best) {
        best = d;
        keep = dropped;
      }
    }
    _dropped.clear();
    if (keep == null) return;
    final (at, point, timeMs) = keep;
    onKeep(from, at, point, timeMs);
  }

  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final l2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (l2 == 0) return (p - a).distance;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / l2).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }

  /// Keeps the stroke's last samples from swelling into an end blob.
  static List<StrokePoint> settleEnd(List<StrokePoint> points) {
    final settled = PressureFilter.settleEnd([for (final p in points) p.pressure]);
    return [
      for (var i = 0; i < points.length; i++) StrokePoint(points[i].x, points[i].y, settled[i]),
    ];
  }

  /// [time] in whole milliseconds (as Android's `MotionEvent` times).
  static int msOf(Duration time) => time.inMicroseconds ~/ 1000;

  /// [e]'s pressure as 0.05..1; 0.5 without a stylus.
  static double pressureOf(PointerEvent e) => normalisedPressure(e, e.pressure);

  /// [raw] pressure (in [e]'s device range) as 0.05..1; 0.5 without a stylus.
  static double normalisedPressure(PointerEvent e, double raw) {
    if (!isStylusKind(e.kind)) return 0.5;
    final range = e.pressureMax - e.pressureMin;
    if (range <= 0) return 0.5;
    return ((raw - e.pressureMin) / range).clamp(0.05, 1.0);
  }
}
