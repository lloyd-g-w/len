import 'dart:math' as math;
import 'dart:typed_data';

/// One-dimensional smoothing filters for uniformly spaced samples, used by
/// `Centerline`. All run in O(n) regardless of the filter width: a Gaussian
/// is approximated by repeated box filters over prefix sums.
abstract final class LineFilters {
  /// Box half-width whose three box passes approximate a Gaussian with
  /// standard deviation [sigma] samples.
  static int halfWidth(double sigma) => ((math.sqrt(4 * sigma * sigma + 1) - 1) / 2).round();

  /// Gaussian blur of [v] in place, mirroring the samples at both ends.
  static void gaussianMirrored(Float64List v, int m) {
    final n = v.length;
    if (n < 3 || m == 0) return;
    final padded = Float64List(n + 6 * m);
    for (var i = 0; i < padded.length; i++) {
      var j = i - 3 * m;
      while (j < 0 || j >= n) {
        j = j < 0 ? -j : 2 * (n - 1) - j;
      }
      padded[i] = v[j];
    }
    _boxPasses(padded, m, 3);
    v.setRange(0, n, padded, 3 * m);
  }

  /// Low-pass filter `2G − G∘G` (G a Gaussian of half-width [m]) of [v],
  /// in place. Its response `1 − (1 − g)²` is flat for features much
  /// larger than the filter, so curves barely shrink, while jitter much
  /// smaller than it is removed.
  ///
  /// Beyond each end, [v] is continued by a quadratic least-squares fit of
  /// its last [fit] samples through the end sample. That keeps the ends in
  /// place and extends the local curvature, so the ends neither lag (a
  /// stroke in progress follows the pen) nor bend.
  static void lowPass(Float64List v, int m, int fit) {
    final n = v.length;
    if (n < 3 || m == 0) return;
    final pad = 6 * m;
    final once = Float64List(n + 2 * pad);
    final (a0, b0) = _endFit(v, fit, fromStart: true);
    final (a1, b1) = _endFit(v, fit, fromStart: false);
    for (var i = 0; i < once.length; i++) {
      final j = i - pad;
      if (j < 0) {
        once[i] = v[0] - a0 * j + b0 * j * j;
      } else if (j >= n) {
        final k = j - (n - 1);
        once[i] = v[n - 1] + a1 * k + b1 * k * k;
      } else {
        once[i] = v[j];
      }
    }
    final twice = Float64List.fromList(once);
    _boxPasses(once, m, 3);
    _boxPasses(twice, m, 6);
    for (var i = 0; i < n; i++) {
      v[i] = 2 * once[i + pad] - twice[i + pad];
    }
  }

  /// Fits `v[end] + a·k + b·k²` to the [fit] samples next to an end, with
  /// k counting outwards (negative inside the line).
  static (double, double) _endFit(Float64List v, int fit, {required bool fromStart}) {
    final n = v.length;
    final q = math.min(fit, n - 1);
    final origin = fromStart ? v[0] : v[n - 1];
    var s2 = 0.0, s3 = 0.0, s4 = 0.0, t1 = 0.0, t2 = 0.0;
    for (var j = 1; j <= q; j++) {
      final k = -j.toDouble();
      final d = (fromStart ? v[j] : v[n - 1 - j]) - origin;
      s2 += k * k;
      s3 += k * k * k;
      s4 += k * k * k * k;
      t1 += k * d;
      t2 += k * k * d;
    }
    if (q < 3) return (s2 == 0 ? 0.0 : t1 / s2, 0.0);
    final det = s2 * s4 - s3 * s3;
    if (det.abs() < 1e-12) return (t1 / s2, 0.0);
    return ((t1 * s4 - t2 * s3) / det, (s2 * t2 - s3 * t1) / det);
  }

  /// [passes] box filters of half-width [m] over [v], in place. Values
  /// within `passes · m` of either end are approximate.
  static void _boxPasses(Float64List v, int m, int passes) {
    final n = v.length;
    final prefix = Float64List(n + 1);
    for (var pass = 0; pass < passes; pass++) {
      for (var i = 0; i < n; i++) {
        prefix[i + 1] = prefix[i] + v[i];
      }
      for (var i = 0; i < n; i++) {
        final lo = math.max(0, i - m), hi = math.min(n, i + m + 1);
        v[i] = (prefix[hi] - prefix[lo]) / (hi - lo);
      }
    }
  }
}
