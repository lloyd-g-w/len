part of 'paper_painter.dart';

/// How [PaperRenderer] sizes and fades pattern lines and dots at a scale,
/// and strengthens them in small page thumbnails.
abstract final class _PatternInk {
  /// Paints [dots] [PaperRenderer.dotRadius] × the look's dot size in world
  /// units, so they scale with the page and the ink. Smaller on screen than
  /// [PaperRenderer.minDotRadius] (far out), they stay that size and fade by
  /// the square root of the area they lost, as lines do by their width (the ink
  /// kept fades slower than the dot shrinks, so far-out paper keeps contrast);
  /// a strengthened page thumbnail ([faint]; 1 for template miniatures) keeps
  /// them at least [PaperRenderer.minMiniatureDot], unfaded.
  static void paintDots(
    Canvas canvas,
    List<Offset> dots,
    Color ink,
    PaperLook look,
    double scale,
    double faint,
  ) {
    final shown = PaperRenderer.dotRadius * look.dotSize * scale;
    final floor = math.max(PaperRenderer.minDotRadius, PaperRenderer.minMiniatureDot * faint);
    final fade = shown >= floor ? 1.0 : ui.lerpDouble(shown / floor, 1, faint)!;
    canvas.drawPoints(
      ui.PointMode.points,
      dots,
      Paint()
        ..color = ink.withValues(alpha: ink.a * fade)
        ..strokeWidth = 2 * math.max(shown, floor) / scale
        ..strokeCap = StrokeCap.round,
    );
  }

  /// The target-pixel width and the opacity of a [weight] line at [scale]. On
  /// the page it is [PaperRenderer.lineWidth] × the look's weight, so it scales
  /// with the page and the ink; thinner than [PaperRenderer.minLineWidth] (far
  /// out) it stays that wide and fades by the square root of the width it lost,
  /// so far-out paper (and a phone's) reads lighter but keeps contrast.
  /// Miniatures ([mini]) keep their lines about a pixel wide (in the weights'
  /// proportions), unfaded; a strengthened page thumbnail ([faint]) at least
  /// [PaperRenderer.minMiniatureLine].
  static (double, double) lineWidth(
    PatternWeight weight,
    PaperLook look,
    double scale, {
    required bool mini,
    required double faint,
  }) {
    final shown = PaperRenderer.lineWidth(weight) * look.lineWeight * scale;
    if (mini) {
      final relative =
          PaperRenderer.lineWidth(weight) /
          PaperRenderer.lineWidth(PatternWeight.normal) *
          look.lineWeight;
      final floor = math.min(1.0, 0.5 + scale) * relative;
      return (math.max(shown, math.max(floor, PaperRenderer.minMiniatureLine * faint)), 1);
    }
    if (shown >= PaperRenderer.minLineWidth) return (shown, 1);
    return (PaperRenderer.minLineWidth, math.sqrt(shown / PaperRenderer.minLineWidth));
  }

  /// How much a page thumbnail at [scale] strengthens its pattern: 0 from
  /// [PaperRenderer.faintScale] up, 1 from [PaperRenderer.faintScaleFull] down.
  static double faintness(double scale) =>
      ((PaperRenderer.faintScale - scale) /
              (PaperRenderer.faintScale - PaperRenderer.faintScaleFull))
          .clamp(0.0, 1.0);

  /// The pattern colour [ink] moved towards the paper's text colour (and made
  /// more opaque) by [faint], for contrast at small sizes.
  static Color strengthen(Color ink, PaperColor color, double faint) {
    if (faint == 0) return ink;
    final darker = Color.lerp(ink.withValues(alpha: 1), color.text, 0.2 * faint)!;
    return darker.withValues(alpha: ink.a + (1 - ink.a) * 0.3 * faint);
  }
}
