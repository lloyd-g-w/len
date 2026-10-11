import 'dart:math' as math;
import 'dart:ui';

/// A Dart model of what the experimental low-latency overlay
/// (`android/.../WetInkOverlay.kt`) draws, so its geometry and timing can
/// be checked against Flutter's ink without a device. Keep in step with
/// the Kotlin code:
///
///  * **Samples**: every digitiser sample of the contact (historical and
///    current, nothing dropped), position in view pixels, time in whole
///    milliseconds (`MotionEvent` times), pressure normalised by the
///    device's range, clamped to 0.05..1 and smoothed by an EMA that keeps
///    0.65 of the previous value (the Kotlin comment claims "same as
///    Dart's PressureFilter", which keeps 0.4).
///  * **Radius**: linear interpolation in the `begin` radius table
///    (`WetInkStyle.radii`, pressure 0, 0.1 … 1) — no stabiliser, no
///    causal radius smoothing, no slope limit, no tapers.
///  * **Shape**: a round-capped line between consecutive samples, stroke
///    width `r[i-1] + r[i]` (so a capsule of the mean radius), no curve
///    fitting; a single sample is a dot.
///  * **Tail**: on every commit (after each Flutter frame's `progress`,
///    and every frame while a tail remains) the front buffer is cleared
///    and only samples newer than
///    `max(progress − 2 frames, now − 5 frames)` are drawn, plus the
///    sample before them (the segment leading in). New samples are drawn
///    into the front buffer as they arrive. After `end`, the tail stays
///    until 2 frames have passed.
class WetInkModel {
  WetInkModel({required this.radii, required this.frameMs});

  /// Radius (same units as positions) at pressures 0, 0.1, … 1.
  final List<double> radii;

  /// Display frame interval.
  final double frameMs;

  final List<WetSample> samples = [];
  double _pressure = -1;

  /// Adds a digitiser sample; [pressure] already normalised to 0..1.
  void add(Offset position, double pressure, int timeMs) {
    final norm = pressure.clamp(0.05, 1.0);
    _pressure = _pressure < 0 ? norm : _pressure * 0.65 + norm * 0.35;
    samples.add(WetSample(position, _pressure, timeMs));
  }

  double radiusAt(double p) {
    if (radii.length == 1) return radii[0];
    final t = p.clamp(0.0, 1.0) * (radii.length - 1);
    final i = math.min(t.floor(), radii.length - 2);
    return radii[i] + (radii[i + 1] - radii[i]) * (t - i);
  }

  /// Index of the first sample the overlay shows at [nowMs], given the
  /// newest `progress` ([flutterUpToMs]) and, after `end`, when it ended.
  /// Equal to the number of samples when it shows nothing.
  int tailStart({required double nowMs, required double flutterUpToMs, double? endedAtMs}) {
    if (endedAtMs != null && nowMs - endedAtMs >= 2 * frameMs) return samples.length;
    final cutoff = math.max(flutterUpToMs - 2 * frameMs, nowMs - 5 * frameMs);
    var from = samples.length;
    while (from > 0 && samples[from - 1].timeMs > cutoff) {
      from--;
    }
    if (from == samples.length) return from;
    return math.max(0, from - 1);
  }

  /// The overlay's segments from sample [from] to [to] (exclusive): each
  /// a round-capped line `(a, b, half width)`; one sample is a dot.
  List<(Offset, Offset, double)> segments(int from, int to) {
    if (to - from == 1) {
      final s = samples[from];
      return [(s.position, s.position, radiusAt(s.pressure))];
    }
    return [
      for (var i = from + 1; i < to; i++)
        (
          samples[i - 1].position,
          samples[i].position,
          (radiusAt(samples[i - 1].pressure) + radiusAt(samples[i].pressure)) / 2,
        ),
    ];
  }
}

/// A sample as the overlay keeps it.
class WetSample {
  const WetSample(this.position, this.pressure, this.timeMs);
  final Offset position;
  final double pressure;
  final int timeMs;
}
