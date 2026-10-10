import 'dart:math' as math;
import 'dart:ui';

/// Unsigned curvature (1 / radius) of the circle through [a], [b], [c].
double curvature(Offset a, Offset b, Offset c) {
  final ab = (b - a).distance, bc = (c - b).distance, ca = (a - c).distance;
  final cross = ((b - a).dx * (c - a).dy - (b - a).dy * (c - a).dx).abs();
  final denom = ab * bc * ca;
  return denom == 0 ? 0 : 2 * cross / denom;
}

/// Signed turn (radians) from direction a→b to b→c.
double turn(Offset a, Offset b, Offset c) {
  final u = b - a, v = c - b;
  return math.atan2(u.dx * v.dy - u.dy * v.dx, u.dx * v.dx + u.dy * v.dy);
}

/// Savitzky–Golay (quadratic) smoothing over ±[m] samples: fits a parabola
/// locally, so real curvature passes through and only bumps remain in the
/// residual `v − sg(v)`. Ends use a shrunken window.
List<double> savitzkyGolay(List<double> v, int m) {
  final n = v.length;
  final out = List<double>.of(v);
  for (var i = 0; i < n; i++) {
    final k = math.min(m, math.min(i, n - 1 - i));
    if (k < 2) continue;
    final norm = (2 * k - 1) * (2 * k + 1) * (2 * k + 3) / 3.0;
    var s = 0.0;
    for (var j = -k; j <= k; j++) {
      s += (3 * k * k + 3 * k - 1 - 5 * j * j) * v[i + j];
    }
    out[i] = s / norm;
  }
  return out;
}

/// Unit normals of a polyline (central differences).
List<Offset> normals(List<Offset> c) => [
  for (var i = 0; i < c.length; i++)
    _normal(c[math.max(0, i - 1)], c[math.min(c.length - 1, i + 1)]),
];

Offset _normal(Offset a, Offset b) {
  final d = b - a;
  final len = d.distance;
  return len == 0 ? Offset.zero : Offset(-d.dy / len, d.dx / len);
}
