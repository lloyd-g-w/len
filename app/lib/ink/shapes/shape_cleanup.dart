import 'dart:math' as math;
import 'dart:ui';

import 'polyline.dart';

/// The tidying a recognised polygon gets ([ShapeRecognizer]): what a hand
/// nearly drew is made exact — square rectangles, equilateral triangles,
/// level bases.
abstract final class ShapeCleanup {
  /// Sides within this share of each other are made equal (squares,
  /// equilateral triangles).
  static const double equalSides = 0.08;

  /// A side within this angle (radians, 6°) of level is made level.
  static const double levelAngle = 6 * math.pi / 180;

  /// [r] (a rectangle in its own frame) as a square around its centre when
  /// its sides are within [equalSides] of each other.
  static Rect square(Rect r) {
    final w = r.width, h = r.height;
    if (w <= 0 || h <= 0 || (w / h - 1).abs() > equalSides) return r;
    return Rect.fromCenter(center: r.center, width: (w + h) / 2, height: (w + h) / 2);
  }

  /// Triangle [c] tidied: equilateral (about its centroid) when its sides
  /// are within [equalSides] of their mean, and turned so a side within
  /// [levelAngle] of level is level.
  static List<Offset> triangle(List<Offset> c) {
    var t = c;
    final sides = [for (var i = 0; i < 3; i++) (t[(i + 1) % 3] - t[i]).distance];
    final mean = (sides[0] + sides[1] + sides[2]) / 3;
    if (sides.every((s) => (s / mean - 1).abs() <= equalSides)) t = _equilateral(t);
    return _levelled(t);
  }

  /// The equilateral triangle nearest [c]: same centroid, mean radius, and
  /// the vertices' mean turn, in the same order.
  static List<Offset> _equilateral(List<Offset> c) {
    final g = Polyline.centroid(c);
    final radius = c.map((p) => (p - g).distance).reduce((a, b) => a + b) / 3;
    // Clockwise or not, vertex i lies ±120°·i from vertex 0.
    final a0 = (c[1] - g).direction - (c[0] - g).direction;
    final turn = math.atan2(math.sin(a0), math.cos(a0)) > 0 ? 1 : -1;
    var x = 0.0, y = 0.0;
    for (var i = 0; i < 3; i++) {
      final a = (c[i] - g).direction - turn * i * 2 * math.pi / 3;
      x += math.cos(a);
      y += math.sin(a);
    }
    final start = math.atan2(y, x);
    return [
      for (var i = 0; i < 3; i++)
        g + Offset.fromDirection(start + turn * i * 2 * math.pi / 3, radius),
    ];
  }

  /// [c] turned about its centroid so its side nearest level (within
  /// [levelAngle]) is level.
  static List<Offset> _levelled(List<Offset> c) {
    var best = double.infinity;
    for (var i = 0; i < c.length; i++) {
      final d = c[(i + 1) % c.length] - c[i];
      var a = math.atan2(d.dy, d.dx);
      a -= (a / math.pi).round() * math.pi; // into (-90°, 90°]
      if (a.abs() < best.abs()) best = a;
    }
    if (best == 0 || best.abs() > levelAngle) return c;
    final g = Polyline.centroid(c);
    final cos = math.cos(-best), sin = math.sin(-best);
    return [
      for (final p in c)
        g + Offset((p - g).dx * cos - (p - g).dy * sin, (p - g).dx * sin + (p - g).dy * cos),
    ];
  }
}
