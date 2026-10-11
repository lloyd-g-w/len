import 'dart:math' as math;
import 'dart:typed_data';

import 'growable.dart';

/// One-dimensional filters for uniformly spaced samples (the stroke
/// pipeline, `StrokeShaper`).
abstract final class LineFilters {
  /// The kernel of the low-pass filter `2G − G∘G` (G a Gaussian with
  /// standard deviation [sigma] samples), centred: `kernel[K + j]` is the
  /// weight of the sample `j` away, `K = (kernel.length − 1) / 2`.
  ///
  /// Its response `1 − (1 − g)²` is flat for features much larger than the
  /// filter, so curves barely shrink, while jitter much smaller than it is
  /// removed. The kernel is finite: an output depends on nothing more than
  /// K samples away, so smoothed ink becomes *final* a fixed distance
  /// behind the pen tip.
  static Float64List lowPassKernel(double sigma) {
    if (sigma <= 0.05) return Float64List.fromList([1]);
    final m = (3 * sigma).ceil();
    final g = Float64List(2 * m + 1);
    var sum = 0.0;
    for (var j = -m; j <= m; j++) {
      sum += g[j + m] = math.exp(-j * j / (2 * sigma * sigma));
    }
    for (var j = 0; j < g.length; j++) {
      g[j] /= sum;
    }
    // G∘G has twice the support.
    final gg = Float64List(4 * m + 1);
    for (var a = 0; a < g.length; a++) {
      for (var b = 0; b < g.length; b++) {
        gg[a + b] += g[a] * g[b];
      }
    }
    final w = Float64List(4 * m + 1);
    for (var j = 0; j < w.length; j++) {
      final gj = j - m >= 0 && j - m < g.length ? g[j - m] : 0.0;
      w[j] = 2 * gj - gg[j];
    }
    // Drop negligible tails (they only widen the not-yet-final zone).
    var k = 2 * m;
    while (k > 1 && w[2 * m - k].abs() < 2e-4) {
      k--;
    }
    final out = Float64List.sublistView(w, 2 * m - k, 2 * m + k + 1).sublist(0);
    var total = 0.0;
    for (final v in out) {
      total += v;
    }
    for (var j = 0; j < out.length; j++) {
      out[j] /= total;
    }
    return out;
  }

  /// Fits `v[end] + a·k + b·k²` to the [fit] samples next to [end] going
  /// inwards in direction [inward] (+1 at a start, −1 at an end), with k
  /// counting outwards (negative inside). Returns (a, b). Used to continue
  /// a stretch beyond its end so a filter neither lags nor bends there.
  static (double, double) endFit(DoubleBuffer v, int end, int inward, int fit) {
    final origin = v[end];
    var s2 = 0.0, s3 = 0.0, s4 = 0.0, t1 = 0.0, t2 = 0.0;
    for (var j = 1; j <= fit; j++) {
      final k = -j.toDouble();
      final d = v[end + inward * j] - origin;
      s2 += k * k;
      s3 += k * k * k;
      s4 += k * k * k * k;
      t1 += k * d;
      t2 += k * k * d;
    }
    if (fit == 0) return (0.0, 0.0);
    if (fit < 3) return (t1 / s2, 0.0);
    final det = s2 * s4 - s3 * s3;
    if (det.abs() < 1e-12) return (t1 / s2, 0.0);
    return ((t1 * s4 - t2 * s3) / det, (s2 * t2 - s3 * t1) / det);
  }
}
