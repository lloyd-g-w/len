import '../pen/pen_profile.dart';
import '../render/stroke_renderer.dart';
import 'live_ink.dart';

/// How a platform overlay should draw the tip of the stroke being written
/// ("low-latency ink"): it paints the newest samples itself, before Flutter
/// can, until Flutter's own rendering of the live stroke catches up.
///
/// Only opaque, round, untextured ink qualifies — anywhere the overlay and
/// Flutter's ink overlap must look the same, which translucent or textured
/// ink would not.
class WetInkStyle {
  const WetInkStyle({required this.color, required this.radii});

  /// Opaque ARGB colour.
  final int color;

  /// Outline radius in logical screen pixels at pressures 0, 0.1, … 1
  /// ([steps] + 1 values); the overlay interpolates between them.
  final List<double> radii;

  static const int steps = 10;

  /// The style of [live]'s stroke seen at viewport [scale], or null when it
  /// cannot be drawn faithfully by an overlay (or is not a free-hand stroke).
  static WetInkStyle? of(LiveInk live, double scale) {
    if (!live.isDrawing || live.straightened) return null;
    final profile = PenProfile.of(live.tool);
    final opaque = live.style.opacity >= 1 && (live.color >>> 24) == 0xFF;
    if (!opaque || profile.flatCaps || profile.textured || profile.nibVariation > 0) return null;
    return WetInkStyle(
      color: live.color,
      radii: [
        for (var i = 0; i <= steps; i++)
          StrokeRenderer.radiusAt(profile, live.width, live.style, i / steps) * scale,
      ],
    );
  }
}
