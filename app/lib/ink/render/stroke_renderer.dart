import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../domain/stroke.dart';
import '../pen/pen_profile.dart';
import 'nib.dart';
import 'pencil_texture.dart';
import 'stroke_outline.dart';

/// Turns stroke points into filled outline paths and paints them.
///
/// Outlines come from [StrokeOutline]; the pen's [PenProfile] and the
/// stroke's [StrokeStyle] decide their shape. Committed strokes are immutable, so their paths are memoised per
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
  /// being drawn (its moving end is not trimmed).
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
        ? Nib.pressures(
            points,
            variation: profile.nibVariation,
            angle: PenProfile.nibAngle,
            thinning: style.thinning,
          )
        : null;
    return StrokeOutline.build(
      points,
      specFor(tool, width, style),
      pressures: pressures,
      complete: complete,
    );
  }

  /// Outline radius for a given [pressure].
  static double radiusAt(PenProfile profile, double width, StrokeStyle style, double pressure) =>
      specFor(profile.tool, width, style).radiusFor(pressure);

  /// The outline shape parameters for a stroke.
  @visibleForTesting
  static OutlineSpec specFor(InkTool tool, double width, StrokeStyle style) {
    final profile = PenProfile.of(tool);
    return OutlineSpec(
      width: width,
      thinning: style.thinning,
      streamline: style.streamline,
      easing: profile.easing,
      taperStart: style.taperStart,
      taperEnd: style.taperEnd,
      flatCaps: profile.flatCaps,
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
}
