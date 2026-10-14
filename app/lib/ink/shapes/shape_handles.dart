import 'dart:math' as math;
import 'dart:ui';

import '../../domain/shape_geometry.dart';
import 'shape_builder.dart';

/// The control points a selected shape shows as handles, and what
/// dragging one does to it:
///  * line, arrow: the two ends, moved freely;
///  * triangle, diamond, polygon: the vertices, moved freely;
///  * rectangle: the corners — the opposite corner stays, the sides keep
///    their directions (a rectangle stays a rectangle);
///  * ellipse: the corners of its bounding box, likewise;
///  * star: the five outer points — turning and sizing the star about its
///    centre — and one inner point, setting the inner radius.
abstract final class ShapeHandles {
  /// World positions of [shape]'s handles, in a fixed order per kind.
  static List<Offset> of(ShapeGeometry shape) {
    final p = shape.points;
    return switch (shape.kind) {
      ShapeKind.ellipse => _ellipseBox(p[0], p[1] - p[0], p[2] - p[0]),
      ShapeKind.star => [
        for (final (i, v) in ShapeBuilder.starVertices(shape).indexed)
          if (i.isEven || i == innerVertex) v,
      ],
      _ => p,
    };
  }

  /// How far [shape] is turned (radians): the direction of a rectangle's
  /// first side, of an ellipse's or star's first axis; 0 for the others,
  /// which have no sides of their own to align a frame with.
  static double angleOf(ShapeGeometry shape) {
    final p = shape.points;
    final d = switch (shape.kind) {
      ShapeKind.rectangle || ShapeKind.ellipse || ShapeKind.star => p[1] - p[0],
      _ => null,
    };
    if (d == null || d.distance == 0) return 0;
    // Within ±45°: a rectangle turned by 90° is the same rectangle.
    const quarter = math.pi / 2;
    final a = d.direction;
    return a - (a / quarter).round() * quarter;
  }

  /// The star vertex whose handle sets the inner radius (between the top
  /// point and the next).
  static const int innerVertex = 1;

  /// Whether handle [index] of [shape] sets a star's inner radius.
  static bool isInner(ShapeGeometry shape, int index) => shape.kind == ShapeKind.star && index == 1;

  /// [shape] with handle [index] dragged to [to].
  static ShapeGeometry drag(ShapeGeometry shape, int index, Offset to) {
    final p = shape.points;
    switch (shape.kind) {
      case ShapeKind.rectangle:
        return ShapeGeometry(shape.kind, _parallelogram(p, index, to));
      case ShapeKind.ellipse:
        final k = _parallelogram(_ellipseBox(p[0], p[1] - p[0], p[2] - p[0]), index, to);
        final c = (k[0] + k[2]) / 2;
        return ShapeGeometry(shape.kind, [c, c + (k[1] - k[0]) / 2, c + (k[3] - k[0]) / 2]);
      case ShapeKind.star:
        return isInner(shape, index) ? _inner(shape, to) : _turnStar(shape, index, to);
      case ShapeKind.line ||
          ShapeKind.arrow ||
          ShapeKind.triangle ||
          ShapeKind.diamond ||
          ShapeKind.polygon:
        return shape.withPoint(index, to);
    }
  }

  /// The corners of the box around the ellipse `c + u·cos t + v·sin t`.
  static List<Offset> _ellipseBox(Offset c, Offset u, Offset v) => [
    c - u - v,
    c + u - v,
    c + u + v,
    c - u + v,
  ];

  /// Parallelogram [k] (corners in order) with corner [i] at [to]: the
  /// opposite corner stays, the sides keep their directions.
  static List<Offset> _parallelogram(List<Offset> k, int i, Offset to) {
    final o = k[(i + 2) % 4];
    var a = k[(i + 1) % 4] - o, b = k[(i + 3) % 4] - o;
    // A side collapsed to nothing has lost its direction: square to the other.
    const tiny = 1e-9;
    if (a.distance < tiny && b.distance < tiny) {
      a = const Offset(1, 0);
      b = const Offset(0, 1);
    } else if (a.distance < tiny) {
      a = Offset(-b.dy, b.dx);
    } else if (b.distance < tiny) {
      b = Offset(a.dy, -a.dx);
    }
    final det = a.dx * b.dy - a.dy * b.dx;
    final d = to - o;
    final s = (d.dx * b.dy - d.dy * b.dx) / det;
    final t = (a.dx * d.dy - a.dy * d.dx) / det;
    return [
      for (var j = 0; j < 4; j++)
        switch ((j - i) % 4) {
          0 => to,
          1 => o + a * s,
          2 => o,
          _ => o + b * t,
        },
    ];
  }

  /// [star] turned and sized about its centre so that outer point
  /// [index] lies at [to].
  static ShapeGeometry _turnStar(ShapeGeometry star, int index, Offset to) {
    final c = star.points[0];
    final from = of(star)[index] - c, target = to - c;
    if (from.distance == 0 || target.distance < 1e-6) return star;
    // The similarity taking `from` to `target` (complex division).
    final n = from.distanceSquared;
    final re = (target.dx * from.dx + target.dy * from.dy) / n;
    final im = (target.dy * from.dx - target.dx * from.dy) / n;
    Offset turn(Offset v) => c + Offset(re * v.dx - im * v.dy, im * v.dx + re * v.dy);
    return star.map((p) => p == c ? c : turn(p - c));
  }

  /// [star] with the inner radius that puts its inner points nearest [to].
  static ShapeGeometry _inner(ShapeGeometry star, Offset to) {
    final [c, a, b] = star.points;
    final u = a - c, v = b - c, d = to - c;
    final det = u.dx * v.dy - u.dy * v.dx;
    if (det == 0) return star;
    // [to] in the star's frame, along the inner point's direction.
    final w = Offset((d.dx * v.dy - d.dy * v.dx) / det, (u.dx * d.dy - u.dy * d.dx) / det);
    final angle = ShapeBuilder.starAngle(innerVertex);
    final inner = (w.dx * math.cos(angle) + w.dy * math.sin(angle)).clamp(
      ShapeGeometry.minInner,
      ShapeGeometry.maxInner,
    );
    return ShapeGeometry(ShapeKind.star, star.points, inner: inner);
  }
}
