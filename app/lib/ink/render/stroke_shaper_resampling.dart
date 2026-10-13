part of 'stroke_shaper.dart';

/// 3. Resampling: samples every [ShapeParams.step] along a centripetal
/// Catmull-Rom spline through the input samples.
extension _Resampling on StrokeShaper {
  void _resample(int start, int n, {required bool ended}) {
    // Final segments: the sample after the segment's end is final (only
    // the last input sample is not: its radius may still grow), and the
    // input must still be growing (an ended stroke's last segments use
    // the end reflection).
    _rx.length = _resFinal;
    _ry.length = _resFinal;
    _rr.length = _resFinal;
    if (_resFinal == 0) {
      _push(_sx[start], _sy[start], _sr[start]);
      _resFinal = 1;
      _seg = start;
      final phase = _phase;
      _next = phase != null && phase > 1e-9 ? phase : p.step;
    }
    _segNext.length = _seg;
    _segFirst.length = _seg;
    while (_seg + 2 <= n - 2 && !ended) {
      _segNext.add(_next);
      _segFirst.add(_rx.length.toDouble());
      _next = _segment(_seg, start, n, _next);
      _seg++;
      _resFinal = _rx.length;
    }
    var next = _next;
    for (var k = _seg; k < n - 1; k++) {
      _segNext.add(next);
      _segFirst.add(_rx.length.toDouble());
      next = _segment(k, start, n, next);
    }
    // The end sample itself (closer than a step to the one before).
    final along = next - p.step; // distance of the last sample before the end
    if (n - 1 > start && along < -p.step * 1e-3) _push(_sx[n - 1], _sy[n - 1], _sr[n - 1]);
  }

  /// Adds the samples of segment [k] (input samples k → k+1) at arc
  /// lengths [next], next + step, …; returns the arc length of the next
  /// sample measured from the start of segment k + 1.
  double _segment(int k, int start, int n, double next) {
    final x1 = _sx[k], y1 = _sy[k], x2 = _sx[k + 1], y2 = _sy[k + 1];
    final lead = k > start || (_leadIn && k > 0);
    final x0 = lead ? _sx[k - 1] : 2 * x1 - x2;
    final y0 = lead ? _sy[k - 1] : 2 * y1 - y2;
    final x3 = k + 2 < n ? _sx[k + 2] : 2 * x2 - x1;
    final y3 = k + 2 < n ? _sy[k + 2] : 2 * y2 - y1;
    final r1 = _sr[k], r2 = _sr[k + 1];
    final gap = _dist(x2 - x1, y2 - y1);
    final pieces = math.max(1, math.min(64, (gap / (p.step * 0.5)).ceil()));
    final cr = _CatmullRom(x0, y0, x1, y1, x2, y2, x3, y3);
    var ax = x1, ay = y1, along = 0.0;
    for (var q = 1; q <= pieces; q++) {
      final t = q / pieces;
      final (bx, by) = q == pieces ? (x2, y2) : cr.at(t);
      final len = _dist(bx - ax, by - ay);
      while (next <= along + len && len > 0) {
        final u = (next - along) / len;
        final tt = (q - 1 + u) / pieces;
        _push(ax + (bx - ax) * u, ay + (by - ay) * u, r1 + (r2 - r1) * tt);
        next += p.step;
      }
      along += len;
      ax = bx;
      ay = by;
    }
    return next - along;
  }

  void _push(double x, double y, double r) {
    _rx.add(x);
    _ry.add(y);
    _rr.add(r);
  }
}

/// The length of a spline segment, flattened as [StrokeShaper] flattens it
/// for [step] (see [StrokeShaper.segmentLength]).
double _splineLength(
  double x0,
  double y0,
  double x1,
  double y1,
  double x2,
  double y2,
  double x3,
  double y3,
  double step,
) {
  final gap = _dist(x2 - x1, y2 - y1);
  final pieces = math.max(1, math.min(64, (gap / (step * 0.5)).ceil()));
  final cr = _CatmullRom(x0, y0, x1, y1, x2, y2, x3, y3);
  var ax = x1, ay = y1, along = 0.0;
  for (var q = 1; q <= pieces; q++) {
    final (bx, by) = q == pieces ? (x2, y2) : cr.at(q / pieces);
    along += _dist(bx - ax, by - ay);
    ax = bx;
    ay = by;
  }
  return along;
}

/// One centripetal Catmull-Rom segment from P1 to P2 (Barry–Goldman form).
class _CatmullRom {
  _CatmullRom(this.x0, this.y0, this.x1, this.y1, this.x2, this.y2, this.x3, this.y3) {
    t1 = _knot(0, x0, y0, x1, y1);
    t2 = _knot(t1, x1, y1, x2, y2);
    t3 = _knot(t2, x2, y2, x3, y3);
  }

  final double x0, y0, x1, y1, x2, y2, x3, y3;
  late final double t1, t2, t3;

  static double _knot(double t, double ax, double ay, double bx, double by) {
    final d = math.sqrt(math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay)));
    return t + math.max(d, 1e-6);
  }

  (double, double) at(double u) {
    final t = t1 + (t2 - t1) * u;
    double lerp(double a, double b, double ta, double tb) =>
        (tb - t) / (tb - ta) * a + (t - ta) / (tb - ta) * b;
    final a1x = lerp(x0, x1, 0, t1), a1y = lerp(y0, y1, 0, t1);
    final a2x = lerp(x1, x2, t1, t2), a2y = lerp(y1, y2, t1, t2);
    final a3x = lerp(x2, x3, t2, t3), a3y = lerp(y2, y3, t2, t3);
    final b1x = lerp(a1x, a2x, 0, t2), b1y = lerp(a1y, a2y, 0, t2);
    final b2x = lerp(a2x, a3x, t1, t3), b2y = lerp(a2y, a3y, t1, t3);
    return (lerp(b1x, b2x, t1, t2), lerp(b1y, b2y, t1, t2));
  }
}
