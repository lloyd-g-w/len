import 'dart:math' as math;

import '../../domain/stroke.dart';

/// "Hold to straighten": turns a freehand stroke into a straight line.
abstract final class Straighten {
  /// A straight line from the first to the last of [points], resampled
  /// every [spacing] world units so tapers and the pixel eraser behave as
  /// on a hand-drawn line. Pressure is the stroke's typical (median)
  /// pressure, so the line keeps the weight the user was writing with.
  static List<StrokePoint> line(List<StrokePoint> points, {double spacing = 2}) {
    if (points.length < 2) return List.of(points);
    final from = points.first, to = points.last;
    final pressure = medianPressure(points);
    final length = math.sqrt(math.pow(to.x - from.x, 2) + math.pow(to.y - from.y, 2));
    final steps = math.max(1, (length / spacing).ceil());
    return [
      for (var i = 0; i <= steps; i++)
        StrokePoint(
          from.x + (to.x - from.x) * i / steps,
          from.y + (to.y - from.y) * i / steps,
          pressure,
        ),
    ];
  }

  static double medianPressure(List<StrokePoint> points) {
    final sorted = [for (final p in points) p.pressure]..sort();
    return sorted[sorted.length ~/ 2];
  }

  /// Total polyline length of [points].
  static double pathLength(List<StrokePoint> points) {
    var length = 0.0;
    for (var i = 1; i < points.length; i++) {
      final dx = points[i].x - points[i - 1].x, dy = points[i].y - points[i - 1].y;
      length += math.sqrt(dx * dx + dy * dy);
    }
    return length;
  }
}
