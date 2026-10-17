import 'dart:math' as math;
import 'dart:ui';

import '../../domain/shape_geometry.dart';
import 'shape_builder.dart';

/// The snaps a pen gets without Shift: lines nearly level, upright or
/// diagonal become exactly so, and shapes nearly regular (squares, circles,
/// equilateral triangles, regular stars) become regular. Shift's own
/// constraints (15° steps, always regular) are [ShapeTool.constrain]'s.
/// Handle drags add finer snaps ([angle], [align]).
abstract final class ShapeSnap {
  /// A line within this angle (radians, 4°) of a multiple of 45° snaps.
  static const double lineTolerance = 4 * math.pi / 180;

  /// A dragged handle within this angle (radians, 2°) of a multiple of 15°
  /// snaps to it.
  static const double fineTolerance = 2 * math.pi / 180;

  /// 15°, the step of Shift's angles and of handles' fine snaps.
  static const double step = math.pi / 12;

  /// A box whose proportions are within this share of a regular shape's
  /// snaps to them.
  static const double regularTolerance = 0.06;

  /// [end] moved, at the same distance from [start], so the line between
  /// them is level, upright or diagonal when it nearly is.
  static Offset lineEnd(Offset start, Offset end) =>
      angle(start, end, step: math.pi / 4, tolerance: lineTolerance);

  /// [end] moved, at the same distance from [start], to the nearest
  /// multiple of [step] when within [tolerance] of it (radians; always
  /// with an infinite one).
  static Offset angle(
    Offset start,
    Offset end, {
    double step = ShapeSnap.step,
    double tolerance = double.infinity,
  }) {
    final d = end - start;
    if (d == Offset.zero) return end;
    final a = d.direction, nearest = (a / step).round() * step;
    if ((a - nearest).abs() > tolerance) return end;
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

  /// [end] with handle snaps (dragged with no Shift): level, upright or
  /// diagonal within [lineTolerance], other 15° steps within
  /// [fineTolerance], seen from [start].
  static Offset handleAngle(Offset start, Offset end) {
    final coarse = lineEnd(start, end);
    return coarse != end ? coarse : angle(start, end, tolerance: fineTolerance);
  }

  /// [p] moved onto the vertical and / or horizontal line through the
  /// nearest of [others] within [tolerance] (each axis apart), so points
  /// line up with each other.
  static Offset align(Offset p, Iterable<Offset> others, double tolerance) {
    if (tolerance <= 0) return p;
    var x = p.dx, y = p.dy;
    var bestX = tolerance, bestY = tolerance;
    for (final o in others) {
      final dx = (o.dx - p.dx).abs(), dy = (o.dy - p.dy).abs();
      if (dx <= bestX) {
        bestX = dx;
        x = o.dx;
      }
      if (dy <= bestY) {
        bestY = dy;
        y = o.dy;
      }
    }
    return Offset(x, y);
  }

  /// [end] kept on the level, upright or diagonal line through [start]
  /// nearest to it (projected onto it): Shift moving one point.
  static Offset axisLock(Offset start, Offset end) {
    final d = end - start;
    if (d == Offset.zero) return end;
    final dir = angle(Offset.zero, d, step: math.pi / 4) / d.distance;
    return start + dir * (d.dx * dir.dx + d.dy * dir.dy);
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
  /// the sides at [angle]: square when nearly so (rectangles' corner
  /// handles).
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

  /// [value] made [target] when within [regularTolerance] of it
  /// (relatively): equal radii, square sides.
  static double equal(double value, double target) =>
      target > 0 && (value.abs() / target - 1).abs() <= regularTolerance
      ? target * value.sign
      : value;
}
