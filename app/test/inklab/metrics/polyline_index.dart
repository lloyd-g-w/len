import 'dart:math' as math;
import 'dart:ui';

/// Nearest-point queries against a polyline, accelerated by a uniform grid
/// of its segments.
class PolylineIndex {
  PolylineIndex(this.points, {this.cell = 4}) {
    for (var i = 0; i + 1 < points.length; i++) {
      final a = points[i], b = points[i + 1];
      final x0 = _c(math.min(a.dx, b.dx)), x1 = _c(math.max(a.dx, b.dx));
      final y0 = _c(math.min(a.dy, b.dy)), y1 = _c(math.max(a.dy, b.dy));
      for (var x = x0; x <= x1; x++) {
        for (var y = y0; y <= y1; y++) {
          (_grid[(x, y)] ??= []).add(i);
        }
      }
    }
  }

  final List<Offset> points;
  final double cell;
  final Map<(int, int), List<int>> _grid = {};

  int _c(double v) => (v / cell).floor();

  /// Distance from [p] to the polyline, and the index of the nearest
  /// segment (its first point).
  ({double distance, int segment}) nearest(Offset p) {
    if (points.length == 1) return (distance: (p - points[0]).distance, segment: 0);
    var best = double.infinity;
    var seg = 0;
    final cx = _c(p.dx), cy = _c(p.dy);
    for (var ring = 0; ring < 1 << 12; ring++) {
      for (var x = cx - ring; x <= cx + ring; x++) {
        for (var y = cy - ring; y <= cy + ring; y++) {
          if ((x - cx).abs() != ring && (y - cy).abs() != ring) continue;
          for (final i in _grid[(x, y)] ?? const <int>[]) {
            final d = segmentDistance(p, points[i], points[i + 1]);
            if (d < best) {
              best = d;
              seg = i;
            }
          }
        }
      }
      // Anything in a farther ring is at least ring × cell away.
      if (best <= ring * cell) break;
      if (ring > 0 && _grid.isEmpty) break;
    }
    return (distance: best, segment: seg);
  }

  double distance(Offset p) => nearest(p).distance;

  static double segmentDistance(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return (p - a).distance;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }
}

/// Cumulative arc length at every point of [path].
List<double> arcLengths(List<Offset> path) {
  final out = <double>[0];
  for (var i = 1; i < path.length; i++) {
    out.add(out.last + (path[i] - path[i - 1]).distance);
  }
  return out;
}
