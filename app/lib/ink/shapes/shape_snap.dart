import 'dart:math' as math;
import 'dart:ui';

import '../../domain/shape_geometry.dart';
import 'shape_builder.dart';

/// The snaps a pen gets without Shift: lines nearly level, upright or
/// diagonal become exactly so, and shapes nearly regular (squares, circles,
/// equilateral triangles, regular stars) become regular. Shift's own
/// constraints (15° steps, always regular) are [ShapeTool.constrain]'s.
abstract final class ShapeSnap {
  /// A line within this angle (radians, 4°) of a multiple of 45° snaps.
  static const double lineTolerance = 4 * math.pi / 180;

  /// A box whose proportions are within this share of a regular shape's
  /// snaps to them.
  static const double regularTolerance = 0.06;

  /// [end] moved, at the same distance from [start], so the line between
  /// them is level, upright or diagonal when it nearly is.
  static Offset lineEnd(Offset start, Offset end) {
    final d = end - start;
    if (d == Offset.zero) return end;
    const step = math.pi / 4;
    final angle = d.direction, nearest = (angle / step).round() * step;
    if ((angle - nearest).abs() > lineTolerance) return end;
    // Exact zeros on the axes (cos(π/2) is not quite 0).
    final quarter = (nearest / (math.pi / 2)).round() * (math.pi / 2);
    if ((nearest - quarter).abs() < 1e-9) {
      final turns = (nearest / (math.pi / 2)).round() % 4;
      final r = d.distance;
      return start +
          switch (turns) {
            0 => Offset(r, 0),
            1 => Offset(0, r),
            2 => Offset(-r, 0),
            _ => Offset(0, -r),
          };
    }
    return start + Offset.fromDirection(nearest, d.distance);
  }

  /// [end] moved so a [kind] dragged from [start] to it is regular when it
  /// nearly is ([regularTolerance]); a line's end as [lineEnd].
  static Offset dragEnd(ShapeKind kind, Offset start, Offset end) {
    if (!kind.isClosed) return lineEnd(start, end);
    final d = end - start;
    if (d.dx == 0 || d.dy == 0) return end;
    final aspect = ShapeBuilder.regularAspect(kind);
    final ratio = d.dx.abs() / d.dy.abs() / aspect;
    if ((ratio - 1).abs() > regularTolerance) return end;
    // Regular, as large as the drag's mean extent.
    final height = (d.dx.abs() / aspect + d.dy.abs()) / 2;
    return start + Offset(height * aspect * d.dx.sign, height * d.dy.sign);
  }

  /// A corner dragged to [world] with the opposite corner at [opposite],
  /// the sides at [angle]: square when nearly so (rectangles' and
  /// ellipses' corner handles).
  static Offset squareCorner(Offset opposite, Offset world, double angle) {
    final d = world - opposite;
    final c = math.cos(angle), s = math.sin(angle);
    final x = d.dx * c + d.dy * s, y = -d.dx * s + d.dy * c;
    if (x == 0 || y == 0) return world;
    if ((x.abs() / y.abs() - 1).abs() > regularTolerance) return world;
    final side = (x.abs() + y.abs()) / 2;
    final lx = side * x.sign, ly = side * y.sign;
    return opposite + Offset(lx * c - ly * s, lx * s + ly * c);
  }
}
