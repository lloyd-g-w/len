import 'dart:math' as math;
import 'dart:ui';

import '../../domain/shape_geometry.dart';
import 'bezier.dart';
import 'shape_builder.dart';

/// Points on a closed shape's outline by the parameter a connector is
/// attached with ([ShapeAttachment.at]): `0 ≤ at < 1` once around, in the
/// shape's own terms (its sides, its angle, its curve's segments), so a
/// point keeps its place on the shape when it is moved, turned, resized
/// or reshaped.
abstract final class ShapeAnchors {
  /// Whether lines and arrows may attach to [shape]: closed outlines.
  static bool isTarget(ShapeGeometry? shape) => shape != null && shape.isClosed;

  /// The point at [at] on [shape]'s outline.
  static Offset pointAt(ShapeGeometry shape, double at) {
    final t = at % 1;
    final p = shape.points;
    switch (shape.kind) {
      case ShapeKind.circle || ShapeKind.ellipse:
        final c = p[0], u = p[1] - c;
        final v = shape.kind == ShapeKind.circle ? Offset(-u.dy, u.dx) : p[2] - c;
        final a = 2 * math.pi * t;
        return c + u * math.cos(a) + v * math.sin(a);
      case ShapeKind.curve:
        final n = p.length ~/ 3, x = t * n, i = math.min(x.floor(), n - 1);
        return Bezier.cubicAt(
          p[3 * i],
          p[3 * i + 1],
          p[3 * i + 2],
          p[(3 * i + 3) % p.length],
          x - i,
        );
      default:
        final v = _vertices(shape);
        final n = v.length, x = t * n, i = math.min(x.floor(), n - 1);
        return Offset.lerp(v[i], v[(i + 1) % n], x - i)!;
    }
  }

  static List<Offset> _vertices(ShapeGeometry shape) =>
      shape.kind == ShapeKind.star ? ShapeBuilder.starVertices(shape) : shape.points;

  /// How many pieces (sides, segments) the parameter runs over.
  static int _pieces(ShapeGeometry shape) => switch (shape.kind) {
    ShapeKind.circle || ShapeKind.ellipse => 4,
    ShapeKind.curve => shape.points.length ~/ 3,
    _ => _vertices(shape).length,
  };

  /// The parameter of the point on [shape]'s outline nearest [p].
  static double nearest(ShapeGeometry shape, Offset p) {
    final n = 48 * _pieces(shape);
    double d(double t) => (pointAt(shape, t) - p).distanceSquared;
    var best = 0.0, bestD = double.infinity;
    for (var i = 0; i < n; i++) {
      final dd = d(i / n);
      if (dd < bestD) (best, bestD) = (i / n, dd);
    }
    // Refine between the neighbouring samples (golden section).
    var lo = best - 1 / n, hi = best + 1 / n;
    const g = 0.6180339887498949;
    for (var k = 0; k < 40; k++) {
      final a = hi - (hi - lo) * g, b = lo + (hi - lo) * g;
      if (d(a) < d(b)) {
        hi = b;
      } else {
        lo = a;
      }
    }
    final t = (lo + hi) / 2;
    return d(t) <= bestD ? t % 1 : best;
  }

  /// The middle of [shape] (of its outline's bounds).
  static Offset centreOf(ShapeGeometry shape) {
    final o = ShapeBuilder.outline(shape);
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final q in o) {
      minX = math.min(minX, q.dx);
      minY = math.min(minY, q.dy);
      maxX = math.max(maxX, q.dx);
      maxY = math.max(maxY, q.dy);
    }
    return Offset((minX + maxX) / 2, (minY + maxY) / 2);
  }

  /// Whether [p] lies inside [shape]'s outline (even–odd).
  static bool contains(ShapeGeometry shape, Offset p) {
    final o = ShapeBuilder.outline(shape);
    var inside = false;
    for (var i = 0, j = o.length - 1; i < o.length; j = i++) {
      final a = o[i], b = o[j];
      if ((a.dy > p.dy) != (b.dy > p.dy) &&
          p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
        inside = !inside;
      }
    }
    return inside;
  }

  /// The parameter of the outline point facing [towards] from [shape]'s
  /// centre: where a line from [towards] to the centre meets the outline
  /// (the outermost crossing of the ray from the centre).
  static double facing(ShapeGeometry shape, Offset towards) {
    final c = centreOf(shape);
    final dir = towards - c;
    if (dir.distance < 1e-9) return nearest(shape, c);
    final o = ShapeBuilder.outline(shape);
    Offset? hit;
    var far = -1.0;
    for (var i = 0; i + 1 < o.length; i++) {
      final s = _ray(c, dir, o[i], o[i + 1]);
      if (s != null && s > far) (far, hit) = (s, c + dir * s);
    }
    return nearest(shape, hit ?? towards);
  }

  /// Where the ray `c + dir·s` (s ≥ 0) crosses segment [a]–[b], as s.
  static double? _ray(Offset c, Offset dir, Offset a, Offset b) {
    final e = b - a;
    final det = dir.dx * -e.dy - dir.dy * -e.dx;
    if (det.abs() < 1e-12) return null;
    final w = a - c;
    final s = (w.dx * -e.dy - w.dy * -e.dx) / det;
    final u = (dir.dx * w.dy - dir.dy * w.dx) / det;
    return s >= 0 && u >= 0 && u <= 1 ? s : null;
  }
}
