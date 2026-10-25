import 'dart:math' as math;
import 'dart:ui';

import '../../domain/shape_geometry.dart';
import 'shape_anchors.dart';
import 'shape_handles.dart';
import 'shape_snap.dart';

/// A shape hold to snap has just made, while the pen that drew it is still
/// down: moving the pen transforms it, live, as Apple Notes and GoodNotes
/// do. [shape] is the snapped shape and [pen] where the pen was then (world):
/// the reference for every later position ([at]).
///
///  * A line or arrow keeps its start (tail) and its free end moves with the
///    pen, so it turns and stretches about its start; level, upright and
///    diagonal snap ([ShapeSnap.lineEnd]).
///  * Any other shape turns by the angle the pen has turned through about
///    the shape's centre and scales evenly by how much farther from (or
///    nearer to) the centre the pen is. A shape with sides or axes of its own
///    (rectangle, diamond, ellipse: [ShapeHandles.angleOf]) snaps level,
///    upright or diagonal within [levelTolerance], others' turn to multiples
///    of 45° within it; any turn to 15° steps within [stepTolerance]; the size
///    as snapped within [sizeTolerance]. Circles stay exactly circles.
class HeldShape {
  HeldShape(this.shape, this.pen)
    : centre = _centreOf(shape),
      _angle = _hasAngle(shape.kind) ? ShapeHandles.angleOf(shape) : null;

  /// The shape as snapped.
  final ShapeGeometry shape;

  /// Where the pen was when it snapped (world).
  final Offset pen;

  /// What the shape turns and scales about.
  final Offset centre;

  /// How far [shape] is turned, if it has sides or axes to level.
  final double? _angle;

  /// A shape's angle snaps level, upright or diagonal within this (radians,
  /// 5°).
  static const double levelTolerance = 5 * math.pi / 180;

  /// A turn snaps to multiples of 15° within this (radians, 2°).
  static const double stepTolerance = 2 * math.pi / 180;

  /// A scale within this share of 1 keeps the snapped size.
  static const double sizeTolerance = 0.03;

  /// The smallest scale: the shape never collapses to a point.
  static const double minScale = 0.05;

  /// Whether [shape] turns and scales about its centre (rather than moving
  /// an end).
  bool get _aboutCentre => shape.kind != ShapeKind.line && shape.kind != ShapeKind.arrow;

  /// The shape with the pen at [to] (world). [minReach] (world units) is
  /// how far from the centre the pen must have been at the snap for turning
  /// and scaling to be meaningful.
  ShapeGeometry at(Offset to, {double minReach = 0}) {
    if (!_aboutCentre) {
      final [tail, tip, ...] = shape.points;
      final end = shape.kind == ShapeKind.line ? to : tip + (to - pen);
      return shape.withPoints([tail, ShapeSnap.lineEnd(tail, end)]);
    }
    final from = pen - centre, now = to - centre;
    if (from.distance <= math.max(minReach, 1e-9) || now.distance == 0) return shape;
    var scale = math.max(minScale, now.distance / from.distance);
    if ((scale - 1).abs() <= sizeTolerance) scale = 1;
    final (turn, quarters) = _snapTurn(_wrap(now.direction - from.direction));
    if (turn == 0 && scale == 1) return shape;
    if (shape.kind == ShapeKind.circle) {
      final [c, rim] = shape.points;
      return shape.withPoints([c, c + Offset((rim - c).distance * scale, 0)]);
    }
    final (cos, sin) = quarters != null ? _quarter(quarters) : (math.cos(turn), math.sin(turn));
    final c = centre;
    Offset f(Offset p) {
      final d = p - c;
      return c + Offset(d.dx * cos - d.dy * sin, d.dx * sin + d.dy * cos) * scale;
    }

    final turned = shape.map(f);
    return quarters == null && _level(turn) ? _squared(turned) : turned;
  }

  /// Whether [turn] leaves the shape's own angle level or upright.
  bool _level(double turn) {
    final a = _angle;
    if (a == null) return false;
    final q = (a + turn) / (math.pi / 2);
    return (q - q.round()).abs() < 1e-9;
  }

  /// [s] (turned level or upright, up to rounding) with its sides or axes
  /// exactly so.
  static ShapeGeometry _squared(ShapeGeometry s) {
    final p = s.points;
    switch (s.kind) {
      case ShapeKind.rectangle:
        final c = (p[0] + p[2]) / 2, u = _axis((p[1] - p[0]) / 2), v = _axis((p[3] - p[0]) / 2);
        return s.withPoints([c - u - v, c + u - v, c + u + v, c - u + v]);
      case ShapeKind.diamond:
        final c = (p[0] + p[2]) / 2, a = _axis((p[2] - p[0]) / 2), b = _axis((p[1] - p[3]) / 2);
        return s.withPoints([c - a, c + b, c + a, c - b]);
      case ShapeKind.ellipse:
        final c = p[0];
        return s.withPoints([c, c + _axis(p[1] - c), c + _axis(p[2] - c)]);
      default:
        return s;
    }
  }

  /// [v] along the nearer axis, as long.
  static Offset _axis(Offset v) => v.dx.abs() >= v.dy.abs()
      ? Offset(v.distance * v.dx.sign, 0)
      : Offset(0, v.distance * v.dy.sign);

  /// [turn] snapped: the shape's own angle level, upright or diagonal, or
  /// the turn itself a multiple of 45° (shapes without an angle), within
  /// [levelTolerance]; else to 15° steps within [stepTolerance]. Also the
  /// number of quarter turns when the turn is exactly that many (so cos and
  /// sin are exact).
  (double, int?) _snapTurn(double turn) {
    const eighth = math.pi / 4;
    final base = _angle ?? 0;
    final level = ((base + turn) / eighth).round() * eighth;
    if ((base + turn - level).abs() <= levelTolerance) {
      final snapped = level - base;
      final q = snapped / (math.pi / 2);
      return (snapped, base == 0 && (q - q.round()).abs() < 1e-12 ? q.round() : null);
    }
    final step = (turn / ShapeSnap.step).round() * ShapeSnap.step;
    if ((turn - step).abs() <= stepTolerance) return (step, null);
    return (turn, null);
  }

  /// cos and sin of [quarters] quarter turns, exactly.
  static (double, double) _quarter(int quarters) => switch (quarters % 4) {
    0 => (1.0, 0.0),
    1 => (0.0, 1.0),
    2 => (-1.0, 0.0),
    _ => (0.0, -1.0),
  };

  /// [a] in (−π, π].
  static double _wrap(double a) {
    var x = a % (2 * math.pi);
    if (x > math.pi) x -= 2 * math.pi;
    return x;
  }

  static bool _hasAngle(ShapeKind kind) => switch (kind) {
    ShapeKind.rectangle || ShapeKind.diamond || ShapeKind.ellipse => true,
    _ => false,
  };

  static Offset _centreOf(ShapeGeometry shape) => switch (shape.kind) {
    ShapeKind.circle || ShapeKind.ellipse || ShapeKind.star => shape.points.first,
    _ => ShapeAnchors.centreOf(shape),
  };
}
