import 'dart:ui' show Offset;

/// Convex-polygon helpers for `QuadDetector`: the hull of a region, its
/// simplification, and the largest quadrilateral inscribed in it.
abstract final class QuadHull {
  /// The convex hull of [points] (Andrew's monotone chain), counter-clockwise
  /// in y-up terms, without collinear points.
  static List<Offset> convexHull(List<Offset> points) {
    final p = [...points]
      ..sort((a, b) => a.dx != b.dx ? a.dx.compareTo(b.dx) : a.dy.compareTo(b.dy));
    if (p.length < 3) return p;
    final hull = <Offset>[];
    void add(Offset q, int floor) {
      while (hull.length > floor && _cross(hull[hull.length - 2], hull.last, q) <= 0) {
        hull.removeLast();
      }
      hull.add(q);
    }

    for (final q in p) {
      add(q, 1);
    }
    final lower = hull.length;
    for (var i = p.length - 2; i >= 0; i--) {
      add(p[i], lower);
    }
    hull.removeLast(); // The first point again.
    return hull;
  }

  /// Drops the hull vertices that matter least (the smallest triangle with
  /// their neighbours, Visvalingam) until at most [maxPoints] remain;
  /// corners of a straight-sided shape survive.
  static List<Offset> simplify(List<Offset> hull, int maxPoints) {
    final p = [...hull];
    while (p.length > maxPoints) {
      var best = 0;
      var bestArea = double.infinity;
      for (var i = 0; i < p.length; i++) {
        final a = _cross(p[(i - 1 + p.length) % p.length], p[i], p[(i + 1) % p.length]).abs();
        if (a < bestArea) {
          bestArea = a;
          best = i;
        }
      }
      p.removeAt(best);
    }
    return p;
  }

  /// The four vertices of the convex polygon [poly] spanning the largest
  /// quadrilateral (exhaustive; keep [poly] small), in polygon order; null
  /// if it has fewer than four.
  static List<Offset>? largestQuad(List<Offset> poly) {
    final n = poly.length;
    if (n < 4) return null;
    var best = -1.0;
    List<Offset>? quad;
    for (var i = 0; i < n - 3; i++) {
      for (var j = i + 1; j < n - 2; j++) {
        for (var k = j + 1; k < n - 1; k++) {
          final t1 = _cross(poly[i], poly[j], poly[k]).abs();
          for (var l = k + 1; l < n; l++) {
            final area = t1 + _cross(poly[i], poly[k], poly[l]).abs();
            if (area > best) {
              best = area;
              quad = [poly[i], poly[j], poly[k], poly[l]];
            }
          }
        }
      }
    }
    return quad;
  }

  /// Twice the signed area of triangle a, b, c.
  static double _cross(Offset a, Offset b, Offset c) =>
      (b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx);
}
