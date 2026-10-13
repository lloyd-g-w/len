/// How hard a stylus presses (its device pressure, normalised to 0..1) maps
/// to the pressure a stroke stores, where 0.5 is medium: the pen's nominal
/// width, and what input without pressure (fingers, a mouse) gets.
///
/// Handwriting presses lightly: an S Pen reports about 0.07–0.34 for most
/// of a line of writing (median 0.13, `real_spen_01`). Taken as is, the
/// ink came out 18 % thinner than the pen's width and barely followed the
/// hand (5 % width change within a stroke). The curve `4p / (3p + 1)` is
/// steep where the hand writes and flat where it presses hard: 0.2 is
/// medium, 0.07 → 0.22, 0.13 → 0.36, 0.34 → 0.67, 1 → 1. Only +, × and ÷,
/// so the low-latency overlay's Kotlin port computes the same bits.
abstract final class PressureCurve {
  /// The stored pressure for a normalised device pressure [p] (0..1).
  static double apply(double p) => 4 * p / (3 * p + 1);

  /// The device pressure that maps to medium (0.5).
  static const double medium = 0.2;
}

/// Cleans up raw stylus pressure before it shapes a stroke.
///
/// Digitisers report noisy pressure, and the sample at pen-up is unreliable:
/// Android attaches the lift event's own pressure to a synthesized final move,
/// which can be far higher than the stroke's real pressure. Because a stroke's
/// end cap is drawn at its last point's radius, such a spike renders as a blob
/// at the end of the line — worse the more pressure-sensitive the pen.
///
/// The filter
///  * smooths samples with an exponential moving average, which removes
///    single-sample spikes while still following deliberate pressure changes
///    within a few samples (stylus input arrives at 120–240 Hz);
///  * ignores the pressure of synthesized samples, reusing the last real one;
///  * never lets the final samples of a stroke swell: the end can only stay
///    level or thin ([settleEnd]).
class PressureFilter {
  PressureFilter({this.smoothing = defaultSmoothing}) : assert(smoothing >= 0 && smoothing < 1);

  /// The default weight kept from the previous value (the low-latency
  /// overlay uses the same).
  static const double defaultSmoothing = 0.4;

  /// Weight kept from the previous value (0 = no smoothing).
  final double smoothing;

  double? _value;

  /// Starts a new stroke.
  void reset() => _value = null;

  /// The filtered pressure for a raw sample. Synthesized samples carry no
  /// trustworthy pressure and repeat the previous value.
  double next(double raw, {bool synthesized = false}) {
    final previous = _value;
    if (previous == null) return _value = raw;
    if (synthesized) return previous;
    return _value = previous * smoothing + raw * (1 - smoothing);
  }

  /// Caps the pressure of the last [count] values so the stroke's tail never
  /// rises above the pressure it had just before; returns the adjusted list.
  static List<double> settleEnd(List<double> pressures, {int count = 3}) {
    if (pressures.length < 2) return pressures;
    final result = List.of(pressures);
    final start = (result.length - count).clamp(1, result.length);
    var ceiling = result[start - 1];
    for (var i = start; i < result.length; i++) {
      if (result[i] > ceiling) result[i] = ceiling;
      ceiling = result[i];
    }
    return result;
  }
}
