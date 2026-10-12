import 'dart:math' as math;

/// The shape of a tapered end, shared by every renderer (committed and live
/// outlines, the low-latency overlay's model and its Kotlin port): over
/// the taper's length the radius is scaled by [factor] of the distance to
/// the end, from the full radius down to a point.
abstract final class Taper {
  /// The radius scale [along] (≥ 0) from the end of a taper [length] long:
  /// `t (2 − t)` of `t = along / length`, so the taper meets the body
  /// without a kink and ends in a point (never below [minFactor]).
  static double factor(double along, double length) {
    if (length <= 0 || along >= length) return 1;
    final t = along / length;
    return math.max(minFactor, t * (2 - t));
  }

  /// The smallest radius scale: the point of a taper.
  static const double minFactor = 0.03;

  /// The end taper is at most this part of the stroke's length (a short
  /// stroke is not all taper).
  static const double maxEndShare = 0.5;

  // ---------------------------------------------------------------------------
  // Following the pen's speed (`PenEnds.followSpeed`)

  /// The end taper's scale for a lift at [speed] (screen px per ms): like
  /// a fountain pen, a quick flick leaves a long tail and a stop a short
  /// one; [referenceSpeed] gives the set length.
  static double speedScale(double speed) =>
      (minSpeedScale + (1 - minSpeedScale) * speed / referenceSpeed).clamp(
        minSpeedScale,
        maxSpeedScale,
      );

  static const double referenceSpeed = 0.8;
  static const double minSpeedScale = 0.25;
  static const double maxSpeedScale = 1.5;

  /// The pen's speed at the lift is measured over the points of the last
  /// [speedWindowMs] (at least the last two).
  static const int speedWindowMs = 20;

  /// The speed (length per ms) over the last [speedWindowMs] of the points
  /// ([x], [y], times [t] in whole ms) [count] so far; 0 for fewer than two.
  static double liftSpeed(
    double Function(int) x,
    double Function(int) y,
    int Function(int) t,
    int count,
  ) {
    if (count < 2) return 0;
    final last = count - 1;
    var from = last - 1;
    while (from > 0 && t(last) - t(from - 1) <= speedWindowMs) {
      from--;
    }
    var length = 0.0;
    for (var i = from + 1; i <= last; i++) {
      final dx = x(i) - x(i - 1), dy = y(i) - y(i - 1);
      length += math.sqrt(dx * dx + dy * dy);
    }
    return length / math.max(1, t(last) - t(from));
  }
}
