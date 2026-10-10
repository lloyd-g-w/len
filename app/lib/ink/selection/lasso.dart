import 'dart:math' as math;
import 'dart:ui';

import '../../domain/stroke.dart';
import '../../domain/surface_element.dart';

/// A closed freehand lasso polygon (world coordinates) and the rules for
/// what it selects.
///
/// **Strokes**: a stroke is selected when at least [strokeShare] of its
/// *length* lies inside the lasso. Measuring length (each segment is
/// subdivided and weighted by its length) rather than counting points makes
/// the rule independent of sampling density: a slow, densely sampled end of
/// a stroke counts no more than a fast, sparse middle, and a two-point
/// straight line is judged by where its length actually is. A dot (single
/// point / zero length) is selected when its point is inside.
///
/// **Elements**: selected when their centre is inside, or when at least
/// half of their outline samples (corners and edge midpoints) are; for
/// elements beneath the ink only the outline rule applies.
class Lasso {
  Lasso(List<Offset> points) : points = List.unmodifiable(points), bounds = _boundsOf(points);

  final List<Offset> points;
  final Rect bounds;

  /// Fraction of a stroke's length that must be inside the lasso.
  static const double strokeShare = 0.5;

  /// Whether the lasso encloses any area at all.
  bool get isValid => points.length >= 3 && bounds.width > 0 && bounds.height > 0;

  /// Even-odd point-in-polygon test (the lasso closes from last to first).
  bool contains(Offset p) {
    if (!bounds.contains(p)) return false;
    var inside = false;
    for (var i = 0, j = points.length - 1; i < points.length; j = i++) {
      final a = points[i], b = points[j];
      if ((a.dy > p.dy) != (b.dy > p.dy) &&
          p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
        inside = !inside;
      }
    }
    return inside;
  }

  /// Share (0..1) of [stroke]'s length inside the lasso.
  double insideShare(Stroke stroke) {
    final pts = stroke.points;
    if (!isValid || !bounds.overlaps(stroke.bounds)) return 0;
    // Pieces no longer than ~1/32 of the lasso, so long straight segments
    // are judged along their length, capped to keep huge strokes cheap.
    final step = math.max(bounds.longestSide / 32, 1e-6);
    var inside = 0.0, total = 0.0;
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1].offset, b = pts[i].offset;
      final length = (b - a).distance;
      if (length == 0) continue;
      final pieces = (length / step).ceil().clamp(1, 16);
      for (var k = 0; k < pieces; k++) {
        final mid = Offset.lerp(a, b, (k + 0.5) / pieces)!;
        if (contains(mid)) inside += length / pieces;
      }
      total += length;
    }
    if (total == 0) return contains(pts.first.offset) ? 1 : 0;
    return inside / total;
  }

  bool selectsStroke(Stroke stroke) => insideShare(stroke) >= strokeShare;

  bool selectsElement(SurfaceElement element) {
    if (!isValid || !bounds.overlaps(element.bounds)) return false;
    // Images beneath the ink are often large backdrops for handwriting:
    // circling ink in their middle must not grab them too.
    if (!element.belowInk && contains(element.rect.center)) return true;
    final c = element.corners;
    final samples = [...c, for (var i = 0; i < 4; i++) Offset.lerp(c[i], c[(i + 1) % 4], 0.5)!];
    return samples.where(contains).length * 2 >= samples.length;
  }

  static Rect _boundsOf(List<Offset> points) {
    if (points.isEmpty) return Rect.zero;
    var r = Rect.fromPoints(points.first, points.first);
    for (final p in points) {
      r = r.expandToInclude(Rect.fromPoints(p, p));
    }
    return r;
  }
}
