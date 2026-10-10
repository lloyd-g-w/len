import 'dart:math' as math;

import '../../domain/stroke.dart';

/// Direction-dependent width of a broad (fountain pen) nib.
abstract final class Nib {
  /// Per-point pressures for [points] scaled by how squarely each point's
  /// direction of travel crosses a nib held at [angle]: strokes along the
  /// nib edge get thinner by up to [variation] (0..1).
  ///
  /// Directions are measured over a few neighbours and then smoothed, so
  /// input jitter does not make the edge ripple.
  static List<double> pressures(
    List<StrokePoint> points, {
    required double variation,
    required double angle,
  }) {
    final n = points.length;
    if (n < 2 || variation <= 0) return [for (final p in points) p.pressure];
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
    return [for (var i = 0; i < n; i++) (points[i].pressure * smoothed[i]).clamp(0.0, 1.0)];
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
