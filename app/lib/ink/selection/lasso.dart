import 'dart:math' as math;
import 'dart:ui';

import '../../domain/stroke.dart';
import '../../domain/surface_element.dart';
import '../stroke_hit_test.dart';
import 'lasso_config.dart';

/// A closed lasso polygon (world coordinates; a freehand loop or a
/// rectangle's corners) and the rules for what it selects, set by its
/// [config] (`LassoConfig.cover` and `kinds`).
///
/// **Strokes**, [LassoCover.mostly]: at least [strokeShare] of a stroke's
/// *length* lies inside. Measuring length (each segment is subdivided and
/// weighted by its length) rather than counting points makes the rule
/// independent of sampling density: a slow, densely sampled end of a stroke
/// counts no more than a fast, sparse middle, and a two-point straight line
/// is judged by where its length actually is. A dot (single point / zero
/// length) is selected when its point is inside. [LassoCover.whole]: every
/// point inside and no segment crossing the outline. [LassoCover.touching]:
/// a point inside or a segment crossing the outline, or (a filled shape)
/// the lasso drawn within its fill.
///
/// **Elements**, [LassoCover.mostly]: their centre is inside, or at least
/// half of their outline samples (corners and edge midpoints) are; for
/// elements beneath the ink only the outline rule applies. [LassoCover.whole]:
/// all corners inside and no edge crossing. [LassoCover.touching]: a corner
/// inside or an edge crossing, or (above the ink only) the lasso drawn
/// within the element: circling ink on an image backdrop doesn't take it.
class Lasso {
  Lasso(List<Offset> points, {this.config = const LassoConfig()})
    : points = List.unmodifiable(points),
      bounds = _boundsOf(points);

  final List<Offset> points;
  final Rect bounds;
  final LassoConfig config;

  /// This lasso moved by [delta], e.g. into the coordinates of another
  /// page of a document (a lasso drawn across pages selects on each).
  Lasso shifted(Offset delta) => Lasso([for (final p in points) p + delta], config: config);

  /// Fraction of a stroke's length that must be inside the lasso
  /// ([LassoCover.mostly]).
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

  /// Whether the segment [a]–[b] crosses the lasso's outline.
  bool crosses(Offset a, Offset b) {
    if (!bounds.overlaps(Rect.fromPoints(a, b).inflate(1e-9))) return false;
    for (var i = 0, j = points.length - 1; i < points.length; j = i++) {
      if (_intersect(a, b, points[j], points[i])) return true;
    }
    return false;
  }

  static double _side(Offset o, Offset a, Offset b) =>
      (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);

  /// Whether segments [p1]–[p2] and [q1]–[q2] properly cross.
  static bool _intersect(Offset p1, Offset p2, Offset q1, Offset q2) {
    final d1 = _side(q1, q2, p1), d2 = _side(q1, q2, p2);
    final d3 = _side(p1, p2, q1), d4 = _side(p1, p2, q2);
    return d1 * d2 < 0 && d3 * d4 < 0;
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

  /// Whether [stroke] is of a kind this lasso takes, and covered enough.
  bool selectsStroke(Stroke stroke) {
    final kind = stroke.tool.isHighlighter ? LassoKind.highlighter : LassoKind.ink;
    if (!config.takes(kind) || !isValid || !bounds.overlaps(stroke.bounds)) return false;
    return switch (config.cover) {
      LassoCover.mostly => insideShare(stroke) >= strokeShare,
      LassoCover.whole => _encloses([for (final p in stroke.points) p.offset]),
      // A lasso drawn within a filled shape touches it, as a tap there does.
      LassoCover.touching =>
        _touches([for (final p in stroke.points) p.offset]) ||
            StrokeHitTest.fillContains(stroke, points.first),
    };
  }

  /// Whether [element] is of a kind this lasso takes, and covered enough.
  bool selectsElement(SurfaceElement element) {
    final kind = element.knownType == ElementType.text ? LassoKind.text : LassoKind.images;
    if (!config.takes(kind) || !isValid || !bounds.overlaps(element.bounds)) return false;
    final c = element.corners;
    final outline = [...c, c.first];
    switch (config.cover) {
      case LassoCover.whole:
        return _encloses(outline);
      case LassoCover.touching:
        // Inside an element above the ink, the lasso touches it; images
        // beneath the ink are backdrops for the ink circled on them.
        return _touches(outline) || (!element.belowInk && element.contains(points.first));
      case LassoCover.mostly:
        // Images beneath the ink are often large backdrops for handwriting:
        // circling ink in their middle must not grab them too.
        if (!element.belowInk && contains(element.rect.center)) return true;
        final samples = [...c, for (var i = 0; i < 4; i++) Offset.lerp(c[i], c[(i + 1) % 4], 0.5)!];
        return samples.where(contains).length * 2 >= samples.length;
    }
  }

  /// Whether the polyline [pts] lies entirely inside.
  bool _encloses(List<Offset> pts) {
    if (!pts.every(contains)) return false;
    for (var i = 1; i < pts.length; i++) {
      if (crosses(pts[i - 1], pts[i])) return false;
    }
    return true;
  }

  /// Whether any of the polyline [pts] is inside or crosses the outline.
  bool _touches(List<Offset> pts) {
    if (pts.any(contains)) return true;
    for (var i = 1; i < pts.length; i++) {
      if (crosses(pts[i - 1], pts[i])) return true;
    }
    return false;
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
