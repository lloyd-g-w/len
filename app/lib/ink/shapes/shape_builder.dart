import 'dart:math' as math;
import 'dart:ui';

import '../../domain/stroke.dart';

/// Builds clean shapes. A shape is an ordinary stroke whose points trace
/// the outline of its [ShapeGeometry] at constant pressure, so it renders,
/// erases, selects and syncs exactly like ink; the geometry
/// ([Stroke.shape]) makes it editable.
abstract final class ShapeBuilder {
  /// The geometry of [kind] dragged from [start] to [end]: the corners of
  /// its bounding box; for lines and arrows, the two ends.
  static ShapeGeometry dragged(ShapeKind kind, Offset start, Offset end) {
    final r = Rect.fromPoints(start, end);
    return switch (kind) {
      ShapeKind.line || ShapeKind.arrow => ShapeGeometry(kind, [start, end]),
      ShapeKind.rectangle || ShapeKind.polygon => ShapeGeometry(kind, [
        r.topLeft,
        r.topRight,
        r.bottomRight,
        r.bottomLeft,
      ]),
      ShapeKind.ellipse => ShapeGeometry(kind, [
        r.center,
        r.center + Offset(r.width / 2, 0),
        r.center + Offset(0, r.height / 2),
      ]),
      ShapeKind.triangle => ShapeGeometry(kind, [r.topCenter, r.bottomRight, r.bottomLeft]),
      ShapeKind.diamond => ShapeGeometry(kind, [
        r.topCenter,
        r.centerRight,
        r.bottomCenter,
        r.centerLeft,
      ]),
      ShapeKind.star => _starIn(r),
    };
  }

  /// The outline vertices of [shape]; closed outlines repeat their first
  /// vertex at the end.
  static List<Offset> outline(ShapeGeometry shape) {
    final p = shape.points;
    return switch (shape.kind) {
      ShapeKind.line => [p[0], p[1]],
      ShapeKind.arrow => arrow(p[0], p[1]),
      ShapeKind.rectangle ||
      ShapeKind.triangle ||
      ShapeKind.diamond ||
      ShapeKind.polygon => [...p, p.first],
      ShapeKind.ellipse => ellipse(p[0], p[1] - p[0], p[2] - p[0]),
      ShapeKind.star => [...starVertices(shape), starVertices(shape).first],
    };
  }

  /// The stroke points of [shape]: its outline at most [spacing] apart, at
  /// constant [pressure].
  static List<StrokePoint> pointsOf(
    ShapeGeometry shape, {
    double spacing = 2,
    double pressure = 0.5,
  }) => points(outline(shape), spacing: spacing, pressure: pressure);

  /// The bounds of an arrowhead's wing length (world units): 18 % of the
  /// arrow within them, and never more than 40 % of it.
  static const double minHead = 12, maxHead = 20;

  /// A shaft from [tail] to [tip] and a two-winged head, as one path that
  /// returns to the tip between the wings.

  static List<Offset> arrow(Offset tail, Offset tip) {
    final v = tip - tail;
    final length = v.distance;
    if (length == 0) return [tail, tip];
    // One size for every arrow (a long axis gets no bigger head than a
    // short link), less on very short ones.
    final head = math.min(length * 0.4, (length * 0.18).clamp(minHead, maxHead));
    final back = -v / length * head;
    const spread = 0.48; // ≈ 27.5°
    return [tail, tip, tip + _turn(back, spread), tip, tip + _turn(back, -spread)];
  }

  /// The ellipse `centre + u·cos t + v·sin t` (u, v: conjugate semi-axes).
  static List<Offset> ellipse(Offset centre, Offset u, Offset v) {
    // Enough segments that the polygon reads as a smooth curve.
    final n = (math.max(u.distance, v.distance) * 0.5).clamp(32, 180).round();
    return [
      for (var i = 0; i <= n; i++)
        centre + u * math.cos(2 * math.pi * i / n) + v * math.sin(2 * math.pi * i / n),
    ];
  }

  static const int starPoints = 5;

  /// The angle (in its frame) of a star's vertex [i]: even ones are the
  /// outer points, from the top, odd ones the inner points between them.
  static double starAngle(int i) => -math.pi / 2 + math.pi * i / starPoints;

  /// A star's ten vertices (outer points at even indices), not closed.
  static List<Offset> starVertices(ShapeGeometry star) {
    final c = star.points[0], u = star.points[1] - c, v = star.points[2] - c;
    return [
      for (var i = 0; i < 2 * starPoints; i++)
        c +
            u * ((i.isEven ? 1.0 : star.inner) * math.cos(starAngle(i))) +
            v * ((i.isEven ? 1.0 : star.inner) * math.sin(starAngle(i))),
    ];
  }

  /// Width over height of the box around [kind] when regular: a circle,
  /// square, equilateral triangle or regular star (Shift while dragging).
  static double regularAspect(ShapeKind kind) => switch (kind) {
    ShapeKind.triangle => 2 / math.sqrt(3),
    ShapeKind.star => 2 * math.sin(2 * math.pi / 5) / (1 + math.cos(math.pi / 5)),
    _ => 1,
  };

  /// A five-pointed star stretched to fill [r]: its frame maps the unit
  /// star's bounding box onto [r].
  static ShapeGeometry _starIn(Rect r) {
    // The unit star spans x ±sin 72°, y from −1 to cos 36°.
    final halfWidth = math.sin(2 * math.pi / 5);
    final bottom = math.cos(math.pi / 5);
    final sx = r.width / (2 * halfWidth), sy = r.height / (1 + bottom);
    final c = Offset(r.center.dx, r.top + sy);
    return ShapeGeometry(ShapeKind.star, [c, c + Offset(sx, 0), c + Offset(0, sy)]);
  }

  static Offset _turn(Offset p, double a) =>
      Offset(p.dx * math.cos(a) - p.dy * math.sin(a), p.dx * math.sin(a) + p.dy * math.cos(a));

  /// Densifies [vertices] to points at most [spacing] apart (keeping every
  /// vertex exactly, so corners stay sharp) at constant [pressure]. Dense
  /// points make the pixel eraser behave as on drawn ink.
  static List<StrokePoint> points(
    List<Offset> vertices, {
    double spacing = 2,
    double pressure = 0.5,
  }) {
    if (vertices.isEmpty) return const [];
    final out = [StrokePoint(vertices.first.dx, vertices.first.dy, pressure)];
    for (var i = 1; i < vertices.length; i++) {
      final a = vertices[i - 1], b = vertices[i];
      final steps = math.max(1, ((b - a).distance / spacing).ceil()).clamp(1, 2000);
      for (var k = 1; k <= steps; k++) {
        final p = Offset.lerp(a, b, k / steps)!;
        out.add(StrokePoint(p.dx, p.dy, pressure));
      }
    }
    return out;
  }

  /// The look of a shape drawn with a pen of [style]: its opacity, zoom
  /// and fill, but an even line with round ends — pressure, tapers, flat
  /// ends and the stabiliser suit handwriting but would thin, notch or
  /// round a shape's corners.
  static StrokeStyle styleFor(StrokeStyle style) =>
      StrokeStyle(opacity: style.opacity, thinning: 0, unit: style.unit).withFill(style.fill);

  /// [stroke] (a shape) reshaped to [shape] as a new stroke [id]: its
  /// outline 2 screen pixels apart at the zoom it was drawn at, same
  /// pressure, look and fill.
  static Stroke reshaped(Stroke stroke, ShapeGeometry shape, {required String id}) {
    final unit = stroke.style.unit;
    return stroke.withPoints(
      pointsOf(shape, spacing: 2 * (unit > 0 ? unit : 1), pressure: stroke.points.first.pressure),
      id: id,
      shape: shape,
    );
  }
}
