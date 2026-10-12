import 'dart:math' as math;
import 'dart:ui';

import '../../domain/stroke.dart';
import 'shape_kind.dart';

/// Builds clean shape outlines. A shape is an ordinary stroke whose points
/// trace the outline at constant pressure, so it renders, erases, selects
/// and syncs exactly like ink.
abstract final class ShapeBuilder {
  /// Outline vertices of [kind] dragged from [start] to [end] (the corners
  /// of its bounding box; for lines and arrows, the two ends). Closed
  /// shapes repeat their first vertex at the end.
  static List<Offset> outline(ShapeKind kind, Offset start, Offset end) {
    final r = Rect.fromPoints(start, end);
    return switch (kind) {
      ShapeKind.line => [start, end],
      ShapeKind.arrow => arrow(start, end),
      ShapeKind.rectangle ||
      ShapeKind.polygon => _close([r.topLeft, r.topRight, r.bottomRight, r.bottomLeft]),
      ShapeKind.ellipse => ellipse(r.center, r.width / 2, r.height / 2),
      ShapeKind.triangle => _close([r.topCenter, r.bottomRight, r.bottomLeft]),
      ShapeKind.diamond => _close([r.topCenter, r.centerRight, r.bottomCenter, r.centerLeft]),
      ShapeKind.star => _star(r),
    };
  }

  /// A shaft from [tail] to [tip] and a two-winged head, as one path that
  /// returns to the tip between the wings.
  static List<Offset> arrow(Offset tail, Offset tip) {
    final v = tip - tail;
    final length = v.distance;
    if (length == 0) return [tail, tip];
    final head = math.min(length * 0.4, math.max(12.0, length * 0.18));
    final back = -v / length * head;
    const spread = 0.48; // ≈ 27.5°
    Offset turn(Offset p, double a) =>
        Offset(p.dx * math.cos(a) - p.dy * math.sin(a), p.dx * math.sin(a) + p.dy * math.cos(a));
    return [tail, tip, tip + turn(back, spread), tip, tip + turn(back, -spread)];
  }

  /// An ellipse with radii [rx] / [ry], rotated by [angle] about [centre].
  static List<Offset> ellipse(Offset centre, double rx, double ry, {double angle = 0}) {
    // Enough segments that the polygon reads as a smooth curve.
    final n = (math.max(rx, ry) * 0.5).clamp(32, 180).round();
    final cos = math.cos(angle), sin = math.sin(angle);
    return [
      for (var i = 0; i <= n; i++)
        () {
          final t = 2 * math.pi * i / n;
          final x = rx * math.cos(t), y = ry * math.sin(t);
          return centre + Offset(x * cos - y * sin, x * sin + y * cos);
        }(),
    ];
  }

  /// A five-pointed star stretched to fill [r].
  static List<Offset> _star(Rect r) {
    const points = 5, inner = 0.42;
    final unit = [
      for (var i = 0; i < points * 2; i++)
        Offset.fromDirection(-math.pi / 2 + math.pi * i / points, i.isEven ? 1.0 : inner),
    ];
    var box = Rect.fromPoints(unit.first, unit.first);
    for (final p in unit) {
      box = box.expandToInclude(Rect.fromPoints(p, p));
    }
    return _close([
      for (final p in unit)
        Offset(
          r.left + (p.dx - box.left) / box.width * r.width,
          r.top + (p.dy - box.top) / box.height * r.height,
        ),
    ]);
  }

  static List<Offset> _close(List<Offset> pts) => [...pts, pts.first];

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

  /// The look of a shape stroke drawn with [style]: no stabiliser (it
  /// would round the corners).
  static StrokeStyle styleFor(StrokeStyle style) => style.copyWith(streamline: 0);
}
