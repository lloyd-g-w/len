import 'dart:math' as math;
import 'dart:ui';

import '../../domain/stroke.dart';
import 'bezier.dart';
import 'polyline.dart';

/// Builds clean shapes. A shape is an ordinary stroke whose points trace
/// the outline of its [ShapeGeometry] at constant pressure, so it renders,
/// erases, selects and syncs exactly like ink; the geometry
/// ([Stroke.shape]) makes it editable.
abstract final class ShapeBuilder {
  /// The geometry of [kind] dragged from [start] to [end]: the corners of
  /// its bounding box; for lines and arrows, the two ends; a square box
  /// makes an ellipse a circle; a curve is an S from end to end.
  static ShapeGeometry dragged(ShapeKind kind, Offset start, Offset end) {
    final r = Rect.fromPoints(start, end);
    return switch (kind) {
      ShapeKind.line || ShapeKind.arrow => ShapeGeometry(kind, [start, end]),
      ShapeKind.circle || ShapeKind.ellipse when r.width == r.height => ShapeGeometry(
        ShapeKind.circle,
        [r.center, r.centerRight],
      ),
      ShapeKind.curve => ShapeGeometry(kind, [
        start,
        start + Offset((end.dx - start.dx) * 0.75, 0),
        end - Offset((end.dx - start.dx) * 0.75, 0),
        end,
      ]),
      ShapeKind.rectangle || ShapeKind.polygon => ShapeGeometry(kind, [
        r.topLeft,
        r.topRight,
        r.bottomRight,
        r.bottomLeft,
      ]),
      ShapeKind.circle || ShapeKind.ellipse => ShapeGeometry(ShapeKind.ellipse, [
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

  /// The outline vertices of [shape], fine enough to read as curves at
  /// [spacing] (world units); closed outlines repeat their first vertex at
  /// the end.
  static List<Offset> outline(ShapeGeometry shape, {double spacing = 2}) {
    final p = shape.points;
    return switch (shape.kind) {
      ShapeKind.line when shape.isBent => Bezier.quadThrough(p[0], p[2], p[1], spacing: spacing),
      ShapeKind.line => [p[0], p[1]],
      ShapeKind.arrow when shape.isBent => _bentArrow(p[0], p[2], p[1], spacing),
      ShapeKind.arrow => arrow(p[0], p[1]),
      ShapeKind.rectangle ||
      ShapeKind.triangle ||
      ShapeKind.diamond ||
      ShapeKind.polygon => [...p, p.first],
      ShapeKind.circle => ellipse(
        p[0],
        p[1] - p[0],
        Offset(p[0].dy - p[1].dy, p[1].dx - p[0].dx),
        spacing: spacing,
      ),
      ShapeKind.ellipse => ellipse(p[0], p[1] - p[0], p[2] - p[0], spacing: spacing),
      ShapeKind.star => [...starVertices(shape), starVertices(shape).first],
      ShapeKind.curve => Bezier.flatten(p, closed: shape.isClosed, spacing: spacing),
    };
  }

  /// The stroke points of [shape]: its outline at most [spacing] apart, at
  /// constant [pressure].
  static List<StrokePoint> pointsOf(
    ShapeGeometry shape, {
    double spacing = 2,
    double pressure = 0.5,
  }) => points(
    outline(shape, spacing: spacing),
    spacing: spacing,
    pressure: pressure,
  );

  /// A bent arrow: the curve from [tail] through [mid] to [tip], its head
  /// along the curve's direction at the tip.
  static List<Offset> _bentArrow(Offset tail, Offset mid, Offset tip, double spacing) {
    final shaft = Bezier.quadThrough(tail, mid, tip, spacing: spacing);
    final control = Bezier.quadControl(tail, mid, tip);
    final head = arrow(control == tip ? tail : control, tip);
    // The straight arrow's head from its tip on, scaled to the curve's
    // length rather than the tangent's.
    final length = Polyline.length(shaft);
    final size = math.min(length * 0.4, (length * 0.18).clamp(minHead, maxHead));
    final back = head[2] - tip;
    final scale = back.distance == 0 ? 0.0 : size / back.distance;
    return [...shaft, tip + (head[2] - tip) * scale, tip, tip + (head[4] - tip) * scale];
  }

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

  /// The ellipse `centre + u·cos t + v·sin t` (u, v: conjugate semi-axes),
  /// its points on the curve at most [spacing] apart (at least 32,
  /// at most [maxEllipsePoints]): the stroke's points then lie on the true
  /// ellipse, which the renderer's spline through them follows at any zoom
  /// (a coarse polygon densified along its sides would show its facets).
  static List<Offset> ellipse(Offset centre, Offset u, Offset v, {double spacing = 2}) {
    // The point moves at most max(|u|, |v|) per radian of t.
    final speed = math.max(u.distance, v.distance);
    final n = (2 * math.pi * speed / math.max(spacing, 1e-6)).ceil().clamp(32, maxEllipsePoints);
    return [
      for (var i = 0; i <= n; i++)
        if (i == n)
          centre + u
        else
          centre + u * math.cos(2 * math.pi * i / n) + v * math.sin(2 * math.pi * i / n),
    ];
  }

  /// The most points an ellipse's outline has.
  static const int maxEllipsePoints = 4096;

  /// The angle (in its frame) of vertex [i] of a star with [tips] points:
  /// even ones are the outer points, from the top, odd ones the inner
  /// points between them.
  static double starAngle(int i, [int tips = ShapeGeometry.defaultTips]) =>
      -math.pi / 2 + math.pi * i / tips;

  /// A star's vertices (outer points at even indices), not closed.
  static List<Offset> starVertices(ShapeGeometry star) {
    final c = star.points[0], u = star.points[1] - c, v = star.points[2] - c;
    return [for (final w in unitStar(star.tips, star.inner)) c + u * w.dx + v * w.dy];
  }

  /// The vertices of a star with [tips] points and [inner] radius in its
  /// frame (outer radius 1).
  static List<Offset> unitStar(int tips, double inner) => [
    for (var i = 0; i < 2 * tips; i++)
      Offset.fromDirection(starAngle(i, tips), i.isEven ? 1.0 : inner),
  ];

  /// Width over height of the box around [kind] when regular: a circle,
  /// square, equilateral triangle or regular star (Shift while dragging).
  static double regularAspect(ShapeKind kind) => switch (kind) {
    ShapeKind.triangle => 2 / math.sqrt(3),
    ShapeKind.star => _unitStarBox.width / _unitStarBox.height,
    _ => 1,
  };

  static final Rect _unitStarBox = Polyline.bounds(
    unitStar(ShapeGeometry.defaultTips, ShapeGeometry.defaultInner),
  );

  /// A star stretched to fill [r]: its frame maps the unit star's bounding
  /// box onto [r].
  static ShapeGeometry _starIn(Rect r) {
    final box = _unitStarBox;
    final sx = r.width / box.width, sy = r.height / box.height;
    final c = Offset(r.left - box.left * sx, r.top - box.top * sy);
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
