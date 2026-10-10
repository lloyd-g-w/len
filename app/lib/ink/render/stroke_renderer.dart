import 'dart:ui';

import 'package:perfect_freehand/perfect_freehand.dart' show PointVector, StrokeOptions, getStroke;

import '../../domain/stroke.dart';

/// Turns stroke points into filled outline paths and paints them.
///
/// Outlines come from `perfect_freehand`, which produces a pressure-aware
/// polygon. Committed strokes are immutable, so their paths are memoised
/// per [Stroke] instance (and garbage-collected with it).
abstract final class StrokeRenderer {
  static final Expando<Path> _paths = Expando('stroke paths');

  /// Highlighter ink is translucent so text underneath stays readable.
  static const double highlighterOpacity = 0.35;

  /// The cached outline path of a committed stroke.
  static Path pathOf(Stroke stroke) => _paths[stroke] ??= buildPath(
        stroke.points,
        tool: stroke.tool,
        width: stroke.width,
        complete: true,
      );

  /// Builds an outline path. [complete] is false while the stroke is still
  /// being drawn, which keeps the tip from overshooting the pen.
  static Path buildPath(
    List<StrokePoint> points, {
    required InkTool tool,
    required double width,
    required bool complete,
  }) {
    if (points.isEmpty) return Path();
    if (points.length == 1) {
      final p = points.single;
      final radius = width * (tool == InkTool.pen ? 0.25 + p.pressure * 0.5 : 0.5);
      return Path()..addOval(Rect.fromCircle(center: p.offset, radius: radius));
    }
    final outline = getStroke(
      [for (final p in points) PointVector(p.x, p.y, p.pressure)],
      options: _optionsFor(tool, width, complete),
    );
    return _smoothPolygon(outline);
  }

  static Paint paintFor(InkTool tool, int argb) {
    final color = Color(argb);
    return Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.fill
      ..color = tool == InkTool.highlighter
          ? color.withValues(alpha: color.a * highlighterOpacity)
          : color;
  }

  static void draw(Canvas canvas, Stroke stroke) =>
      canvas.drawPath(pathOf(stroke), paintFor(stroke.tool, stroke.color));

  static StrokeOptions _optionsFor(InkTool tool, double width, bool complete) {
    return switch (tool) {
      InkTool.pen => StrokeOptions(
          size: width,
          thinning: 0.6,
          smoothing: 0.5,
          streamline: 0.35,
          simulatePressure: false,
          isComplete: complete,
        ),
      InkTool.highlighter => StrokeOptions(
          size: width,
          thinning: 0,
          smoothing: 0.5,
          streamline: 0.5,
          simulatePressure: false,
          isComplete: complete,
        ),
    };
  }

  /// Joins outline points with quadratic curves through their midpoints,
  /// which gives smooth edges without extra points.
  static Path _smoothPolygon(List<Offset> pts) {
    final path = Path();
    if (pts.length < 3) {
      if (pts.isNotEmpty) path.addPolygon(pts, true);
      return path;
    }
    path.moveTo(pts[0].dx, pts[0].dy);
    for (var i = 0; i < pts.length; i++) {
      final p0 = pts[i];
      final p1 = pts[(i + 1) % pts.length];
      path.quadraticBezierTo(p0.dx, p0.dy, (p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
    }
    return path..close();
  }
}
