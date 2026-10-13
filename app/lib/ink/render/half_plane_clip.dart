import 'dart:math' as math;

import 'flat_ends.dart';
import 'outline_sink.dart';

/// An [OutlineSink] that cuts each contour off at a line before passing it
/// on: what lies beyond [line] (on the side its normal faces) is dropped.
/// A flat end's last pieces are cut off at its butt cap so (`FlatEnds`).
///
/// A contour that stays on this side is passed on unchanged; one that
/// crosses the line is flattened (curves and arcs to within [tolerance])
/// and clipped as a polygon.
class HalfPlaneClip implements OutlineSink {
  HalfPlaneClip(this.inner, this.line, this.tolerance);

  final OutlineSink inner;
  final EndLine line;
  final double tolerance;

  // The current contour: its verbs (to replay unchanged) and flattened.
  final List<void Function(OutlineSink)> _verbs = [];
  final List<double> _xs = [], _ys = [];
  double _x = 0, _y = 0;
  bool _beyond = false;

  // Points within a hair of the line count as on this side (a butt cap
  // lies on it).
  double _side(double x, double y) => (x - line.px) * line.nx + (y - line.py) * line.ny - 1e-9;

  void _point(double x, double y) {
    _xs.add(x);
    _ys.add(y);
    if (_side(x, y) > 0) _beyond = true;
    _x = x;
    _y = y;
  }

  @override
  void moveTo(double x, double y) {
    _flush();
    _verbs.add((s) => s.moveTo(x, y));
    _point(x, y);
  }

  @override
  void lineTo(double x, double y) {
    _verbs.add((s) => s.lineTo(x, y));
    _point(x, y);
  }

  @override
  void cubicTo(double x1, double y1, double x2, double y2, double x3, double y3) {
    _verbs.add((s) => s.cubicTo(x1, y1, x2, y2, x3, y3));
    final x0 = _x, y0 = _y;
    // Second differences bound how far the curve strays from its chords.
    final ddx = math.max((x0 - 2 * x1 + x2).abs(), (x1 - 2 * x2 + x3).abs());
    final ddy = math.max((y0 - 2 * y1 + y2).abs(), (y1 - 2 * y2 + y3).abs());
    final dd = math.sqrt(ddx * ddx + ddy * ddy);
    final n = math.max(1, math.min(256, math.sqrt(0.75 * dd / tolerance).ceil()));
    for (var i = 1; i <= n; i++) {
      final t = i / n, u = 1 - t;
      _point(
        u * u * u * x0 + 3 * u * u * t * x1 + 3 * u * t * t * x2 + t * t * t * x3,
        u * u * u * y0 + 3 * u * u * t * y1 + 3 * u * t * t * y2 + t * t * t * y3,
      );
    }
  }

  @override
  void arc(double cx, double cy, double radius, double start, double sweep) {
    _verbs.add((s) => s.arc(cx, cy, radius, start, sweep));
    // An arc starts with a line from the current point to its start.
    final step = radius <= tolerance ? math.pi / 2 : 2 * math.acos(1 - tolerance / radius);
    final n = math.max(1, math.min(1024, (sweep.abs() / step).ceil()));
    for (var i = 0; i <= n; i++) {
      final a = start + sweep * i / n;
      _point(cx + radius * math.cos(a), cy + radius * math.sin(a));
    }
  }

  @override
  void close() {
    _verbs.add((s) => s.close());
    _flush();
  }

  /// Passes the current contour on: unchanged, or clipped.
  void _flush() {
    if (_xs.isEmpty) return;
    if (!_beyond) {
      for (final v in _verbs) {
        v(inner);
      }
    } else {
      _clip();
    }
    _verbs.clear();
    _xs.clear();
    _ys.clear();
    _beyond = false;
  }

  /// The polygon's part on this side (Sutherland–Hodgman against one line:
  /// right for any polygon, the cut edges running along the line).
  void _clip() {
    final n = _xs.length;
    var started = false;
    void emit(double x, double y) {
      if (started) {
        inner.lineTo(x, y);
      } else {
        inner.moveTo(x, y);
        started = true;
      }
    }

    for (var i = 0; i < n; i++) {
      final j = (i + 1) % n;
      final ax = _xs[i], ay = _ys[i], bx = _xs[j], by = _ys[j];
      final sa = _side(ax, ay), sb = _side(bx, by);
      if (sa <= 0) emit(ax, ay);
      if ((sa <= 0) != (sb <= 0)) {
        final t = sa / (sa - sb);
        emit(ax + (bx - ax) * t, ay + (by - ay) * t);
      }
    }
    if (started) inner.close();
  }
}
