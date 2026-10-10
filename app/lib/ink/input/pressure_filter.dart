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
///    level or taper ([settleEnd]).
class PressureFilter {
  PressureFilter({this.smoothing = 0.4}) : assert(smoothing >= 0 && smoothing < 1);

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
