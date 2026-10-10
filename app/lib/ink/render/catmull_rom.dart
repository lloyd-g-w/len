import 'dart:math' as math;

/// Densifies sparse input samples along a centripetal Catmull-Rom spline.
///
/// Digitisers (and Flutter, which delivers at most one sample per pointer
/// event) report a fast stroke as points several units apart. Joining them
/// with straight lines turns every curve into a chain of facets that reads
/// as jitter. The centripetal variant (alpha = 0.5) passes through every
/// sample without overshooting, looping or forming cusps, so it adds no
/// shape that the pen did not draw.
abstract final class CatmullRom {
  /// Returns ([x], [y], [r]) with extra points inserted so that consecutive
  /// points are at most about [maxGap] apart. Radii are interpolated
  /// linearly. Inputs with fewer than three points are returned unchanged.
  static ({List<double> x, List<double> y, List<double> r}) densify(
    List<double> px,
    List<double> py,
    List<double> pr,
    double maxGap,
  ) {
    final n = px.length;
    if (n < 3 || maxGap <= 0) return (x: px, y: py, r: pr);
    final x = <double>[px[0]], y = <double>[py[0]], r = <double>[pr[0]];
    for (var i = 0; i < n - 1; i++) {
      final i0 = math.max(0, i - 1), i3 = math.min(n - 1, i + 2);
      final gap = _dist(px[i + 1] - px[i], py[i + 1] - py[i]);
      final steps = (gap / maxGap).ceil().clamp(1, 64);
      final seg = _Segment(
        px[i0],
        py[i0],
        px[i],
        py[i],
        px[i + 1],
        py[i + 1],
        px[i3],
        py[i3],
        firstIsCopy: i0 == i,
        lastIsCopy: i3 == i + 1,
      );
      for (var k = 1; k <= steps; k++) {
        final t = k / steps;
        if (k == steps) {
          x.add(px[i + 1]);
          y.add(py[i + 1]);
        } else {
          final (sx, sy) = seg.at(t);
          x.add(sx);
          y.add(sy);
        }
        r.add(pr[i] + (pr[i + 1] - pr[i]) * t);
      }
    }
    return (x: x, y: y, r: r);
  }

  static double _dist(double dx, double dy) => math.sqrt(dx * dx + dy * dy);
}

/// One centripetal Catmull-Rom segment from P1 to P2 (Barry–Goldman form).
class _Segment {
  _Segment(
    double x0,
    double y0,
    this.x1,
    this.y1,
    this.x2,
    this.y2,
    double x3,
    double y3, {
    required bool firstIsCopy,
    required bool lastIsCopy,
  }) {
    // At the stroke's ends there is no outer neighbour; reflect the inner
    // one so the end segment starts/finishes in its own direction.
    this.x0 = firstIsCopy ? 2 * x1 - x2 : x0;
    this.y0 = firstIsCopy ? 2 * y1 - y2 : y0;
    this.x3 = lastIsCopy ? 2 * x2 - x1 : x3;
    this.y3 = lastIsCopy ? 2 * y2 - y1 : y3;
    t1 = _knot(0, this.x0, this.y0, x1, y1);
    t2 = _knot(t1, x1, y1, x2, y2);
    t3 = _knot(t2, x2, y2, this.x3, this.y3);
  }

  late final double x0, y0, x3, y3;
  final double x1, y1, x2, y2;
  late final double t1, t2, t3;

  /// Knot spacing |P_{i+1} - P_i|^0.5 (centripetal), never zero.
  static double _knot(double t, double ax, double ay, double bx, double by) {
    final d = math.sqrt(math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay)));
    return t + math.max(d, 1e-6);
  }

  /// The point at fraction [u] (0..1) of the way from P1 to P2.
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
