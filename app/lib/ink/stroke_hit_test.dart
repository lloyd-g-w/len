import 'dart:math' as math;
import 'dart:ui';

import '../domain/stroke.dart';
import 'render/stroke_renderer.dart';

/// Geometry used by the erasers.
abstract final class StrokeHitTest {
  /// Whether the eraser swept along segment [a]→[b] with [radius] touches
  /// [stroke]'s ink (its pressure-dependent outline, see [inkRadius]) or,
  /// unless [fill] is false, a filled shape's fill ([fillContains]).
  static bool sweepHits(Stroke stroke, Offset a, Offset b, double radius, {bool fill = true}) {
    final sweep = Rect.fromPoints(a, b).inflate(radius);
    if (!sweep.overlaps(stroke.bounds)) return false;
    // A sweep reaching into the fill either crosses the outline (below) or
    // starts inside it.
    if (fill && fillContains(stroke, a)) return true;

    final pts = stroke.points;
    if (pts.length == 1) {
      final reach = radius + inkRadius(stroke, pts.single);
      return _pointSegmentDistSq(pts.single.offset, a, b) <= reach * reach;
    }
    var previousRadius = inkRadius(stroke, pts.first);
    for (var i = 0; i < pts.length - 1; i++) {
      final nextRadius = inkRadius(stroke, pts[i + 1]);
      final reach = radius + math.max(previousRadius, nextRadius);
      if (segmentDistSq(pts[i].offset, pts[i + 1].offset, a, b) <= reach * reach) {
        return true;
      }
      previousRadius = nextRadius;
    }
    return false;
  }

  /// Whether [p] lies in [stroke]'s fill (a filled shape, [Stroke.fill];
  /// non-zero winding, as it is painted).
  static bool fillContains(Stroke stroke, Offset p) {
    if (stroke.fill == null || !stroke.bounds.contains(p)) return false;
    final pts = stroke.points;
    var winding = 0;
    for (var i = 0; i < pts.length; i++) {
      final s = pts[i], e = pts[(i + 1) % pts.length];
      if (s.y <= p.dy) {
        if (e.y > p.dy && _side(s, e, p) > 0) winding++;
      } else if (e.y <= p.dy && _side(s, e, p) < 0) {
        winding--;
      }
    }
    return winding != 0;
  }

  static double _side(StrokePoint s, StrokePoint e, Offset p) =>
      (e.x - s.x) * (p.dy - s.y) - (p.dx - s.x) * (e.y - s.y);

  /// Half the ink's thickness at [point] of [stroke], as rendered: the
  /// nominal width scaled by pressure and thinning.
  static double inkRadius(Stroke stroke, StrokePoint point) =>
      StrokeRenderer.specFor(stroke.width, stroke.style).radiusFor(point.pressure);

  /// Squared distance between segments p1-p2 and q1-q2.
  static double segmentDistSq(Offset p1, Offset p2, Offset q1, Offset q2) {
    if (_segmentsIntersect(p1, p2, q1, q2)) return 0;
    return math.min(
      math.min(_pointSegmentDistSq(p1, q1, q2), _pointSegmentDistSq(p2, q1, q2)),
      math.min(_pointSegmentDistSq(q1, p1, p2), _pointSegmentDistSq(q2, p1, p2)),
    );
  }

  static double _pointSegmentDistSq(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lenSq == 0) return (p - a).distanceSquared;
    final ap = p - a;
    final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / lenSq).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distanceSquared;
  }

  static bool _segmentsIntersect(Offset p1, Offset p2, Offset q1, Offset q2) {
    double cross(Offset o, Offset a, Offset b) =>
        (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);
    final d1 = cross(q1, q2, p1);
    final d2 = cross(q1, q2, p2);
    final d3 = cross(p1, p2, q1);
    final d4 = cross(p1, p2, q2);
    return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
  }
}
