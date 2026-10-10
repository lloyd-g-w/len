import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:perfect_freehand/perfect_freehand.dart'
    show PointVector, StrokeEndOptions, StrokeOptions, getStroke;

import '../../domain/stroke.dart';
import '../pen/pen_profile.dart';
import 'nib.dart';
import 'pencil_texture.dart';

/// Turns stroke points into filled outline paths and paints them.
///
/// Outlines come from `perfect_freehand`, which produces a pressure-aware
/// polygon; the pen's [PenProfile] and the stroke's [StrokeStyle] decide its
/// shape. Committed strokes are immutable, so their paths are memoised per
/// [Stroke] instance (and garbage-collected with it).
abstract final class StrokeRenderer {
  static final Expando<Path> _paths = Expando('stroke paths');

  /// The cached outline path of a committed stroke.
  static Path pathOf(Stroke stroke) => _paths[stroke] ??= buildPath(
    stroke.points,
    tool: stroke.tool,
    width: stroke.width,
    style: stroke.style,
    complete: true,
  );

  /// Builds an outline path. [complete] is false while the stroke is still
  /// being drawn, which keeps the tip from overshooting the pen.
  static Path buildPath(
    List<StrokePoint> points, {
    required InkTool tool,
    required double width,
    required StrokeStyle style,
    required bool complete,
  }) {
    if (points.isEmpty) return Path();
    final profile = PenProfile.of(tool);
    final pressures = profile.nibVariation > 0
        ? Nib.pressures(points, variation: profile.nibVariation, angle: PenProfile.nibAngle)
        : null;
    if (points.length == 1) {
      final p = points.single;
      final radius = radiusAt(profile, width, style, pressures?.single ?? p.pressure);
      return Path()..addOval(Rect.fromCircle(center: p.offset, radius: radius));
    }
    final outline = getStroke([
      for (var i = 0; i < points.length; i++)
        PointVector(points[i].x, points[i].y, pressures?[i] ?? points[i].pressure),
    ], options: optionsFor(tool, width, style, complete: complete));
    return _smoothPolygon(outline);
  }

  /// Outline radius for a given [pressure] (mirrors perfect_freehand).
  static double radiusAt(PenProfile profile, double width, StrokeStyle style, double pressure) {
    final t = 0.5 - style.thinning * (0.5 - pressure);
    return (width * profile.easing(t.clamp(0.0, 1.0))).clamp(0.25, width);
  }

  /// The perfect_freehand options for a stroke.
  @visibleForTesting
  static StrokeOptions optionsFor(
    InkTool tool,
    double width,
    StrokeStyle style, {
    required bool complete,
  }) {
    final profile = PenProfile.of(tool);
    final cap = !profile.flatCaps;
    return StrokeOptions(
      size: width,
      thinning: style.thinning,
      smoothing: profile.smoothing,
      streamline: style.streamline,
      easing: profile.easing,
      simulatePressure: false,
      isComplete: complete,
      start: StrokeEndOptions.start(
        cap: cap,
        taperEnabled: style.taperStart > 0,
        customTaper: style.taperStart > 0 ? style.taperStart : null,
      ),
      end: StrokeEndOptions.end(
        cap: cap,
        taperEnabled: style.taperEnd > 0,
        customTaper: style.taperEnd > 0 ? style.taperEnd : null,
      ),
    );
  }

  /// The fill paint for ink of [tool] in colour [argb] with [style].
  static Paint paintFor(InkTool tool, int argb, StrokeStyle style) {
    final color = Color(argb);
    final ink = color.withValues(alpha: color.a * style.opacity);
    final paint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.fill;
    if (PenProfile.of(tool).textured) {
      return paint
        ..shader = PencilTexture.shader()
        ..colorFilter = ColorFilter.mode(ink, BlendMode.srcIn);
    }
    return paint..color = ink;
  }

  static void draw(Canvas canvas, Stroke stroke) =>
      canvas.drawPath(pathOf(stroke), paintFor(stroke.tool, stroke.color, stroke.style));

  /// Joins outline points with quadratic curves through their midpoints,
  /// which gives smooth edges without extra points.
  static Path _smoothPolygon(List<Offset> pts) {
    final path = Path();
    if (pts.length < 3) {
      if (pts.isNotEmpty) path.addPolygon(pts, true);
      return path;
    }
    path.moveTo((pts[0].dx + pts[1].dx) / 2, (pts[0].dy + pts[1].dy) / 2);
    for (var i = 1; i <= pts.length; i++) {
      final p0 = pts[i % pts.length];
      final p1 = pts[(i + 1) % pts.length];
      path.quadraticBezierTo(p0.dx, p0.dy, (p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
    }
    return path..close();
  }
}
