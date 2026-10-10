import 'dart:math' as math;
import 'dart:typed_data';

import 'line_filters.dart';

/// A stroke's centre line resampled at a uniform arc-length [step], with an
/// outline radius per sample.
///
/// Uniform spacing makes every filter below act over a fixed *distance*
/// rather than a number of input samples, so the result does not depend on
/// how fast the pen moved or how often the digitiser reported.
class Centerline {
  Centerline(this.x, this.y, this.r, this.step);

  final Float64List x, y, r;

  /// Distance between consecutive samples.
  final double step;

  /// Sample indices of sharp reversals (see [findCorners]); smoothing never
  /// crosses them and the outline is split there.
  List<int> corners = const [];

  int get length => x.length;

  /// Total length of the centre line.
  double get arcLength => step * (length - 1);

  /// Resamples the polyline ([px], [py]) with radii [pr] at the largest
  /// uniform spacing not exceeding [maxStep], interpolating linearly.
  factory Centerline.resample(List<double> px, List<double> py, List<double> pr, double maxStep) {
    final m = px.length;
    final along = Float64List(m);
    for (var i = 1; i < m; i++) {
      along[i] = along[i - 1] + _dist(px[i] - px[i - 1], py[i] - py[i - 1]);
    }
    final total = along[m - 1];
    final n = total == 0 ? 1 : math.max(1, (total / maxStep).ceil());
    final step = total == 0 ? 0.0 : total / n;
    final x = Float64List(n + 1), y = Float64List(n + 1), r = Float64List(n + 1);
    var j = 0;
    for (var k = 0; k <= n; k++) {
      final s = k == n ? total : k * step;
      while (j < m - 2 && along[j + 1] < s) {
        j++;
      }
      final j1 = math.min(j + 1, m - 1);
      final seg = along[j1] - along[j];
      final t = seg <= 0 ? 0.0 : ((s - along[j]) / seg).clamp(0.0, 1.0);
      x[k] = px[j] + (px[j1] - px[j]) * t;
      y[k] = py[j] + (py[j1] - py[j]) * t;
      r[k] = pr[j] + (pr[j1] - pr[j]) * t;
    }
    if (total == 0) {
      // A single point: keep one sample.
      return Centerline(
        Float64List.fromList([px[0]]),
        Float64List.fromList([py[0]]),
        Float64List.fromList([pr.reduce(math.max)]),
        0,
      );
    }
    return Centerline(x, y, r, step);
  }

  /// Low-pass filters the positions at scale [sigma] (world units) with
  /// [LineFilters.lowPass]: jitter goes, loops keep their size, and the
  /// ends stay where the pen was (no lag while drawing).
  ///
  /// Each stretch between [corners] is filtered on its own, so the tip of a
  /// sharp turn (the top of an "n", the point of a "v") stays put instead of
  /// being pulled back into the stroke.
  void smoothPositions(double sigma) {
    if (step == 0) return;
    final m = LineFilters.halfWidth(sigma / step);
    if (m == 0) return;
    final fit = (2 * sigma / step).ceil();
    final bounds = [0, ...corners, length - 1];
    for (var k = 1; k < bounds.length; k++) {
      final from = bounds[k - 1], to = bounds[k] + 1;
      LineFilters.lowPass(Float64List.sublistView(x, from, to), m, fit);
      LineFilters.lowPass(Float64List.sublistView(y, from, to), m, fit);
    }
  }

  /// Finds where the line doubles back: the direction from [baseline]
  /// behind a sample to it and from it to [baseline] ahead differ by more
  /// than [minTurn] radians. Keeps the sharpest sample of each such spot.
  void findCorners(double baseline, {double minTurn = 2.3}) {
    final k = step == 0 ? 0 : (baseline / step).ceil();
    if (k == 0 || length < 2 * k + 1) return;
    final found = <int>[];
    var best = -1;
    var bestTurn = 0.0;
    for (var i = k; i < length - k; i++) {
      final ax = x[i] - x[i - k], ay = y[i] - y[i - k];
      final bx = x[i + k] - x[i], by = y[i + k] - y[i];
      final turn = math.atan2(ax * by - ay * bx, ax * bx + ay * by).abs();
      if (turn > minTurn) {
        if (turn > bestTurn) {
          best = i;
          bestTurn = turn;
        }
      } else if (best >= 0) {
        found.add(best);
        best = -1;
        bestTurn = 0;
      }
    }
    if (best >= 0) found.add(best);
    corners = found;
  }

  /// Gaussian-smooths the radii with standard deviation [sigma].
  void smoothRadii(double sigma) {
    if (step > 0) LineFilters.gaussianMirrored(r, LineFilters.halfWidth(sigma / step));
  }

  /// Limits how fast the radius may change along the line to [slope]
  /// (radius units per unit of length), only ever shrinking radii, so a
  /// pressure jump becomes a smooth swell instead of a bump.
  void limitRadiusSlope(double slope) {
    final d = slope * step;
    for (var i = 1; i < length; i++) {
      r[i] = math.min(r[i], r[i - 1] + d);
    }
    for (var i = length - 2; i >= 0; i--) {
      r[i] = math.min(r[i], r[i + 1] + d);
    }
  }

  /// Makes both ends non-swelling: over the last [reach] of length at either
  /// end the radius may only stay level or shrink towards the tip, so
  /// pressure spikes at pen-down or pen-up can never become blobs.
  void settleEnds(double reach) {
    final k = step == 0 ? 0 : math.min(length - 1, (reach / step).ceil());
    for (var i = length - k; i < length; i++) {
      if (i > 0) r[i] = math.min(r[i], r[i - 1]);
    }
    for (var i = k - 1; i >= 0; i--) {
      if (i < length - 1) r[i] = math.min(r[i], r[i + 1]);
    }
  }

  /// Narrows the radius towards the ends over [start] / [end] lengths.
  void taper(double start, double end) {
    final total = arcLength;
    start = math.min(start, total / 2);
    end = math.min(end, total / 2);
    if (start <= 0 && end <= 0) return;
    double ease(double t) => t * (2 - t);
    for (var i = 0; i < length; i++) {
      final s = i * step;
      var f = 1.0;
      if (start > 0) f = math.min(f, ease((s / start).clamp(0.0, 1.0)));
      if (end > 0) f = math.min(f, ease(((total - s) / end).clamp(0.0, 1.0)));
      r[i] = math.max(0.02, r[i] * f);
    }
  }

  static double _dist(double dx, double dy) => math.sqrt(dx * dx + dy * dy);
}
