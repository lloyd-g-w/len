import 'dart:math' as math;
import 'dart:ui';

import '../../domain/shape_geometry.dart';
import 'bezier.dart';
import 'shape_builder.dart';
import 'shape_handles.dart';
import 'shape_snap.dart';

/// What dragging each of a shape's handles ([ShapeHandles.of]) does:
///  * an end of a line or arrow moves it (a bend keeps its place on the
///    turned and stretched curve); Shift: 15° steps about the other end;
///    level, upright, diagonal and 15° angles snap;
///  * the bend bends it through the pointer (straight again near the
///    middle; Shift or near it: a symmetric arc);
///  * a rectangle's corner moves with the opposite one fixed and the sides
///    keeping their directions (Shift: proportions; nearly square snaps);
///    a side's middle moves that side (Shift: proportions about the
///    opposite side's middle; nearly square snaps);
///  * a diamond's vertex moves along its axis with the opposite vertex
///    fixed, a side's middle sizes it from the opposite side, as the sides
///    and corners of the box it is drawn in (same Shift and snaps);
///  * a triangle's or polygon's vertex moves freely, lining up with the
///    others (Shift: level, upright or diagonal from where it was);
///  * a centre moves the shape;
///  * a circle's radius sizes it evenly, the end of one of its axes sizes
///    that axis alone (an ellipse; Shift: both, so still a circle; equal
///    radii snap); an ellipse's radius sizes one axis (Shift: both,
///    proportions kept; the other radius snaps), and equal radii make it a
///    circle;
///  * a star's point turns and sizes it about its centre (15° turns snap;
///    Shift: in 15° steps), its inner point sets the inner radius (a
///    regular star's snaps);
///  * a curve's anchor moves with its tangents (lining up with the other
///    anchors; Shift: one axis); a tangent handle turns and sizes its
///    tangent, the opposite one turning with it when they were in line (a
///    smooth anchor), and snaps to its anchor (a corner) or to 15°
///    angles (Shift: in 15° steps).
class ShapeDrags {
  ShapeDrags(this.shape, {this.shift = false, this.snap = 0});

  final ShapeGeometry shape;
  final bool shift;

  /// How near snaps catch (world units); 0: none.
  final double snap;

  bool get _snaps => snap > 0;

  List<Offset> get _p => shape.points;

  /// [shape] with handle [index] at [to].
  ShapeGeometry drag(int index, Offset to) {
    if (ShapeHandles.of(shape)[index].role == HandleRole.centre) {
      final d = to - _p[0];
      return shape.map((p) => p + d);
    }
    return switch (shape.kind) {
      ShapeKind.line || ShapeKind.arrow => index == 2 ? _bend(to) : _end(index, to),
      ShapeKind.rectangle => shape.withPoints(
        index < 4 ? _corner(_p, index, to) : _side(_p, index - 4, to),
      ),
      ShapeKind.diamond => _diamond(index, to),
      ShapeKind.triangle || ShapeKind.polygon => shape.withPoint(index, _free(index, to)),
      ShapeKind.circle => index == 1 ? _radius(to) : _squash(index, to),
      ShapeKind.ellipse => _axis(index, to),
      ShapeKind.star => index == 1 ? _turnStar(to) : _inner(to),
      ShapeKind.curve => index % 3 == 0 ? _anchor(index, to) : _tangent(index, to),
    };
  }

  // Lines and arrows -----------------------------------------------------

  ShapeGeometry _end(int index, Offset to) {
    final other = _p[1 - index];
    final end = shift
        ? ShapeSnap.angle(other, to)
        : _snaps
        ? ShapeSnap.handleAngle(other, to)
        : to;
    final ends = index == 0 ? [end, other] : [other, end];
    if (!shape.isBent) return shape.withPoints(ends);
    // The bend keeps its place relative to the ends (a similarity).
    final from = _p[1] - _p[0], onto = ends[1] - ends[0];
    if (from.distance == 0) return shape.withPoints([...ends, _p[2] + (ends[0] - _p[0])]);
    return shape.withPoints([...ends, ends[0] + _similar(_p[2] - _p[0], from, onto)]);
  }

  ShapeGeometry _bend(Offset to) {
    final a = _p[0], b = _p[1], mid = (a + b) / 2;
    final chord = b - a;
    if (chord.distance == 0) return shape;
    final normal = Offset(-chord.dy, chord.dx) / chord.distance;
    final across = (to - mid).dx * normal.dx + (to - mid).dy * normal.dy;
    final symmetric = mid + normal * across;
    if (_snaps && (to - mid).distance <= snap) return shape.withPoints([a, b]);
    if (shift || (_snaps && (to - symmetric).distance <= snap)) {
      return shape.withPoints([a, b, symmetric]);
    }
    return shape.withPoints([a, b, to]);
  }

  /// [v] turned and scaled as [from] is to [onto] (complex multiplication).
  static Offset _similar(Offset v, Offset from, Offset onto) {
    final n = from.distanceSquared;
    final re = (onto.dx * from.dx + onto.dy * from.dy) / n;
    final im = (onto.dy * from.dx - onto.dx * from.dy) / n;
    return Offset(re * v.dx - im * v.dy, im * v.dx + re * v.dy);
  }

  // Rectangles and diamonds ---------------------------------------------

  /// Parallelogram [k] with corner [i] dragged to [to]: the opposite
  /// corner stays, the sides keep their directions.
  List<Offset> _corner(List<Offset> k, int i, Offset to) {
    final o = k[(i + 2) % 4];
    var target = to;
    if (shift) {
      final diagonal = k[i] - o, d = to - o;
      if (diagonal != Offset.zero) {
        final t = (d.dx * diagonal.dx + d.dy * diagonal.dy) / diagonal.distanceSquared;
        target = o + diagonal * t;
      }
    } else if (_snaps) {
      target = ShapeSnap.squareCorner(o, to, (k[(i + 1) % 4] - o).direction);
    }
    final (a, b) = _sides(k[(i + 1) % 4] - o, k[(i + 3) % 4] - o);
    final det = a.dx * b.dy - a.dy * b.dx;
    final d = target - o;
    final s = (d.dx * b.dy - d.dy * b.dx) / det;
    final t = (a.dx * d.dy - a.dy * d.dx) / det;
    return [
      for (var j = 0; j < 4; j++)
        switch ((j - i) % 4) {
          0 => target,
          1 => o + a * s,
          2 => o,
          _ => o + b * t,
        },
    ];
  }

  /// Sides [a] and [b] from a corner, a collapsed one given the direction
  /// square to the other (it has lost its own).
  static (Offset, Offset) _sides(Offset a, Offset b) {
    const tiny = 1e-9;
    if (a.distance < tiny && b.distance < tiny) return (const Offset(1, 0), const Offset(0, 1));
    if (a.distance < tiny) return (Offset(-b.dy, b.dx), b);
    if (b.distance < tiny) return (a, Offset(a.dy, -a.dx));
    return (a, b);
  }

  /// Parallelogram [k] with side [i] (corners i, i + 1) moved through
  /// [to], along the other sides; the opposite side stays.
  List<Offset> _side(List<Offset> k, int i, Offset to) {
    final c0 = k[i], c1 = k[(i + 1) % 4], c2 = k[(i + 2) % 4], c3 = k[(i + 3) % 4];
    final e = c1 - c0;
    final (d, _) = _sides(c0 - c3, e);
    var s = ((to - c3).dx * d.dx + (to - c3).dy * d.dy) / d.distanceSquared;
    if (_snaps && !shift) s = ShapeSnap.equal(s * d.distance, e.distance) / d.distance;
    if (!shift) return _order(i, [c3 + d * s, c2 + d * s, c2, c3]);
    // Proportions kept: the side's length scales too, about the middle of
    // the opposite side.
    final old = (c0 - c3).distance;
    final scale = old == 0 ? 1.0 : (d * s).distance / old;
    final o = (c2 + c3) / 2;
    final b3 = o - e * (scale / 2), b2 = o + e * (scale / 2);
    return _order(i, [b3 + d * s, b2 + d * s, b2, b3]);
  }

  /// Corners [c0, c1, c2, c3] (from corner [i] on) back in their order.
  static List<Offset> _order(int i, List<Offset> c) => [for (var j = 0; j < 4; j++) c[(j - i) % 4]];

  ShapeGeometry _diamond(int index, Offset to) {
    final v = _p, c = (v[0] + v[1] + v[2] + v[3]) / 4;
    // The box the diamond is drawn in: corner m + 1 between vertices m and
    // m + 1, so vertex m is the middle of box side m.
    final box = [for (var m = 0; m < 4; m++) v[(m + 3) % 4] + v[m] - c];
    final List<Offset> k;
    if (index < 4) {
      k = _side(box, index, to);
    } else {
      // The middle of the diamond's side m is halfway from the centre to
      // box corner m + 1: the pointer moves that corner, the opposite stays.
      final corner = (index - 4 + 1) % 4, opposite = box[(corner + 2) % 4];
      k = _corner(box, corner, (to * 4 - opposite) / 3);
    }
    return shape.withPoints([for (var m = 0; m < 4; m++) (k[m] + k[(m + 1) % 4]) / 2]);
  }

  // Free points -----------------------------------------------------------

  Offset _free(int index, Offset to) {
    if (shift) return ShapeSnap.axisLock(_p[index], to);
    if (!_snaps) return to;
    return ShapeSnap.align(to, [
      for (final (i, p) in _p.indexed)
        if (i != index) p,
    ], snap);
  }

  // Circles, ellipses, stars ---------------------------------------------

  /// The circle sized evenly so that its radius handle (on the rim between
  /// its axes) lies as far from the centre as [to].
  ShapeGeometry _radius(Offset to) {
    final c = _p[0], u = _p[1] - c, r = (to - c).distance;
    if (r < 1e-6 || u == Offset.zero) return shape;
    return shape.withPoints([c, c + u / u.distance * r]);
  }

  /// The circle with axis [index] − 1 sized alone (an ellipse), as the
  /// ellipse's radius handle there would.
  ShapeGeometry _squash(int index, Offset to) {
    final c = _p[0];
    final (u, v) = ShapeHandles.circleAxes(shape);
    final ellipse = ShapeGeometry(ShapeKind.ellipse, [c, c + u, c + v]);
    return ShapeDrags(ellipse, shift: shift, snap: snap)._axis(index - 1, to);
  }

  ShapeGeometry _axis(int index, Offset to) {
    final c = _p[0], axis = _p[index] - c, other = _p[3 - index] - c;
    if (axis == Offset.zero) return shape;
    final d = to - c;
    var length = ((d.dx * axis.dx + d.dy * axis.dy) / axis.distance).abs();
    if (_snaps && !shift) length = ShapeSnap.equal(length, other.distance);
    length = math.max(length, 1e-6);
    final scale = length / axis.distance;
    final a = c + axis * scale, b = c + (shift ? other * scale : other);
    final points = index == 1 ? [c, a, b] : [c, b, a];
    // Equal radii: a circle.
    if ((length - (b - c).distance).abs() <= 1e-9 * length) {
      return ShapeGeometry(ShapeKind.circle, points.sublist(0, 2));
    }
    return shape.withPoints(points);
  }

  /// The star turned and sized about its centre so that its top point lies
  /// at [to].
  ShapeGeometry _turnStar(Offset to) {
    final c = _p[0];
    final target = shift
        ? ShapeSnap.angle(c, to)
        : _snaps
        ? ShapeSnap.handleAngle(c, to)
        : to;
    final from = ShapeBuilder.starVertices(shape)[0] - c;
    if (from.distance == 0 || (target - c).distance < 1e-6) return shape;
    return shape.map((p) => c + _similar(p - c, from, target - c));
  }

  /// The inner radius that puts the star's inner points nearest [to].
  ShapeGeometry _inner(Offset to) {
    final [c, a, b] = _p;
    final u = a - c, v = b - c, d = to - c;
    final det = u.dx * v.dy - u.dy * v.dx;
    if (det == 0) return shape;
    // [to] in the star's frame, along the inner point's direction.
    final w = Offset((d.dx * v.dy - d.dy * v.dx) / det, (u.dx * d.dy - u.dy * d.dx) / det);
    final angle = ShapeBuilder.starAngle(ShapeHandles.innerVertex, shape.tips);
    var inner = w.dx * math.cos(angle) + w.dy * math.sin(angle);
    final regular = regularInner(shape.tips);
    if (_snaps && regular != null && (inner - regular).abs() <= 0.03) inner = regular;
    return shape.withStar(inner: inner.clamp(ShapeGeometry.minInner, ShapeGeometry.maxInner));
  }

  /// The inner radius of a regular star with [tips] points (its sides in
  /// line from point to point), if it has one (five points or more).
  static double? regularInner(int tips) =>
      tips < 5 ? null : math.cos(2 * math.pi / tips) / math.cos(math.pi / tips);

  // Curves ------------------------------------------------------------------

  ShapeGeometry _anchor(int index, Offset to) {
    final p = [..._p];
    var target = to;
    if (shift) {
      target = ShapeSnap.axisLock(p[index], to);
    } else if (_snaps) {
      target = ShapeSnap.align(to, [
        for (var i = 0; i < p.length; i += 3)
          if (i != index) p[i],
      ], snap);
    }
    final d = target - p[index];
    for (final i in [index - 1, index, index + 1]) {
      final j = shape.isClosed ? i % p.length : i;
      if (j >= 0 && j < p.length) p[j] += d;
    }
    return shape.withPoints(p);
  }

  ShapeGeometry _tangent(int index, Offset to) {
    final p = [..._p];
    final anchor = ShapeHandles.anchorOf(shape, index);
    final a = p[anchor];
    var target = to;
    if (shift) {
      target = ShapeSnap.angle(a, to);
    } else if (_snaps) {
      target = (to - a).distance <= snap ? a : ShapeSnap.handleAngle(a, to);
    }
    final o = index % 3 == 1 ? anchor - 1 : anchor + 1;
    final opposite = shape.isClosed ? o % p.length : o;
    if (opposite >= 0 && opposite < p.length && target != a) {
      final mine = p[index] - a, theirs = p[opposite] - a;
      // In line before (a smooth anchor): it stays smooth.
      final smooth =
          mine != Offset.zero &&
          theirs != Offset.zero &&
          Bezier.angleBetween(mine, theirs) > math.pi - smoothTolerance;
      if (smooth) p[opposite] = a - (target - a) / (target - a).distance * theirs.distance;
    }
    p[index] = target;
    return shape.withPoints(p);
  }

  /// Tangents within this angle (radians, 3°) of being in line count as a
  /// smooth anchor.
  static const double smoothTolerance = 3 * math.pi / 180;
}
