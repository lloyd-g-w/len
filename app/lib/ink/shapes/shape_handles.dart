import 'dart:math' as math;
import 'dart:ui';

import '../../domain/shape_geometry.dart';
import 'shape_builder.dart';
import 'shape_drags.dart';

/// What a shape's handle does, which also sets how it looks.
enum HandleRole {
  /// A corner, vertex, end or anchor: moves that point.
  vertex,

  /// The middle of a side: moves the side. On a circle, the end of an
  /// axis: sizes that axis alone, squashing it into an ellipse.
  edge,

  /// The centre of a circle, ellipse or star: moves the shape.
  centre,

  /// The end of a radius: sizes the shape about its centre (a star's
  /// point also turns it).
  radius,

  /// The middle of a line or arrow: bends it.
  bend,

  /// A star's inner point: its inner radius.
  inner,

  /// A curve's tangent handle (drawn with an arm to its anchor).
  tangent;

  /// Handles shown even where others crowd them; the rest step aside
  /// (`SelectionChrome.shapeHandles`).
  bool get isPrimary => this == vertex || this == radius || this == inner;
}

/// One handle of a selected shape: where it is, its role, and for a
/// tangent the anchor it pulls from.
class ShapeHandle {
  const ShapeHandle(this.at, this.role, {this.anchor});

  final Offset at;
  final HandleRole role;
  final Offset? anchor;

  @override
  String toString() => 'ShapeHandle($at, ${role.name})';
}

/// The handles a selected shape shows, by meaning rather than its box,
/// in a fixed order per kind ([of]); dragging one ([drag]) follows
/// [ShapeDrags]:
///  * line, arrow: the two ends, then the bend (the curve's middle, or the
///    middle of a straight one);
///  * rectangle: the four corners, then the middles of the four sides;
///  * diamond: the four vertices, then the middles of its sides;
///  * triangle, polygon: the vertices;
///  * circle: the centre, the radius (on the rim between its axes: sizes it
///    evenly) and the ends of its two axes (sizing one alone makes it an
///    ellipse, whose radii are where they were);
///  * ellipse: the centre and the ends of its two radii;
///  * star: the centre, the top point (size and turn) and an inner point
///    (inner radius);
///  * curve: through points, the points it passes through; a plain spline
///    every control point: anchors and their tangent handles.
abstract final class ShapeHandles {
  /// [shape]'s handles, in a fixed order per kind.
  static List<ShapeHandle> of(ShapeGeometry shape) {
    final p = shape.points;
    List<ShapeHandle> vertices(List<Offset> v) => [
      for (final q in v) ShapeHandle(q, HandleRole.vertex),
    ];
    List<ShapeHandle> sides(List<Offset> v) => [
      for (var i = 0; i < v.length; i++)
        ShapeHandle((v[i] + v[(i + 1) % v.length]) / 2, HandleRole.edge),
    ];
    return switch (shape.kind) {
      ShapeKind.line || ShapeKind.arrow => [
        ...vertices([p[0], p[1]]),
        ShapeHandle(shape.isBent ? p[2] : (p[0] + p[1]) / 2, HandleRole.bend),
      ],
      ShapeKind.rectangle || ShapeKind.diamond => [...vertices(p), ...sides(p)],
      ShapeKind.triangle || ShapeKind.polygon => vertices(p),
      ShapeKind.circle => _circle(shape),
      ShapeKind.ellipse => [
        ShapeHandle(p[0], HandleRole.centre),
        ShapeHandle(p[1], HandleRole.radius),
        ShapeHandle(p[2], HandleRole.radius),
      ],
      ShapeKind.star => [
        ShapeHandle(p[0], HandleRole.centre),
        ShapeHandle(ShapeBuilder.starVertices(shape)[0], HandleRole.radius),
        ShapeHandle(ShapeBuilder.starVertices(shape)[innerVertex], HandleRole.inner),
      ],
      ShapeKind.curve when shape.through != null => vertices(shape.through!),
      ShapeKind.curve => [
        for (var i = 0; i < p.length; i++)
          i % 3 == 0
              ? ShapeHandle(p[i], HandleRole.vertex)
              : ShapeHandle(p[i], HandleRole.tangent, anchor: p[anchorOf(shape, i)]),
      ],
    };
  }

  static List<ShapeHandle> _circle(ShapeGeometry circle) {
    final c = circle.points[0];
    final (u, v) = circleAxes(circle);
    return [
      ShapeHandle(c, HandleRole.centre),
      ShapeHandle(c + (u + v) / math.sqrt2, HandleRole.radius),
      ShapeHandle(c + u, HandleRole.edge),
      ShapeHandle(c + v, HandleRole.edge),
    ];
  }

  /// A circle's two axes (radius vectors): to its rim point and a quarter
  /// turn on, as its outline runs ([ShapeBuilder.outline]).
  static (Offset, Offset) circleAxes(ShapeGeometry circle) {
    final u = circle.points[1] - circle.points[0];
    return (u, Offset(-u.dy, u.dx));
  }

  /// The index of the anchor curve point [index] belongs to (itself for
  /// an anchor).
  static int anchorOf(ShapeGeometry curve, int index) => switch (index % 3) {
    0 => index,
    1 => index - 1,
    _ => (index + 1) % curve.points.length,
  };

  /// Where curve tangent [index] would point with no length of its own:
  /// along its segment (the segment's other control point).
  static Offset tangentTowards(ShapeGeometry curve, int index) {
    final p = curve.points;
    return index % 3 == 1 ? p[index + 1] : p[index - 1];
  }

  /// How far [shape] is turned (radians): the direction of a rectangle's
  /// first side, a diamond's left-to-right diagonal, an ellipse's or
  /// star's first axis; 0 for the others, which have no sides of their own
  /// to align a frame with.
  static double angleOf(ShapeGeometry shape) {
    final p = shape.points;
    final d = switch (shape.kind) {
      ShapeKind.rectangle || ShapeKind.ellipse || ShapeKind.star => p[1] - p[0],
      ShapeKind.diamond => p[1] - p[3],
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

  /// [shape] with handle [index] dragged to [to]. [shift] constrains the
  /// drag (proportions, 15° steps, one axis); [snap] (world units, 0 for
  /// none) is how near snaps catch: alignment with other points, square
  /// and round proportions, straight lines, level angles.
  static ShapeGeometry drag(
    ShapeGeometry shape,
    int index,
    Offset to, {
    bool shift = false,
    double snap = 0,
  }) => ShapeDrags(shape, shift: shift, snap: snap).drag(index, to);
}
