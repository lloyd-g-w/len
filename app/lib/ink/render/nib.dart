import 'dart:math' as math;

import '../../domain/stroke.dart';

/// Direction-dependent width of a broad (fountain pen) nib.
abstract final class Nib {
  /// Per-point pressures for [points], adjusted so that the outline radius
  /// (`∝ 0.5 - thinning * (0.5 - pressure)` with linear easing, see
  /// [OutlineSpec.radiusFor]) shrinks by up to [variation] (0..1) where the direction
  /// of travel runs along a nib held at [angle].
  ///
  /// The effect needs pressure sensitivity: with [thinning] 0 the width
  /// cannot vary, and small values limit how thin hairlines get.
  /// Directions are measured over a few neighbours and then smoothed, so
  /// input jitter does not make the edge ripple.
  static List<double> pressures(
    List<StrokePoint> points, {
    required double variation,
    required double angle,
    required double thinning,
  }) {
    final n = points.length;
    if (n < 2 || variation <= 0 || thinning <= 0) return [for (final p in points) p.pressure];
    const reach = 3;
    final factors = List<double>.filled(n, 1);
    for (var i = 0; i < n; i++) {
      final a = points[math.max(0, i - reach)];
      final b = points[math.min(n - 1, i + reach)];
      final dx = b.x - a.x, dy = b.y - a.y;
      if (dx == 0 && dy == 0) {
        factors[i] = i > 0 ? factors[i - 1] : 1 - variation / 2;
        continue;
      }
      final across = math.sin(math.atan2(dy, dx) - angle).abs();
      factors[i] = 1 - variation * (1 - across);
    }
    final smoothed = _smooth(factors, 3);
    return [
      for (var i = 0; i < n; i++)
        () {
          final size = 0.5 - thinning * (0.5 - points[i].pressure);
          final p = 0.5 - (0.5 - size * smoothed[i]) / thinning;
          return p.clamp(0.0, 1.0);
        }(),
    ];
  }

  /// Moving average over a window of `2 * radius + 1` values.
  static List<double> _smooth(List<double> values, int radius) {
    final n = values.length;
    return List.generate(n, (i) {
      var sum = 0.0;
      var count = 0;
      for (var j = math.max(0, i - radius); j <= math.min(n - 1, i + radius); j++) {
        sum += values[j];
        count++;
      }
      return sum / count;
    });
  }
}
