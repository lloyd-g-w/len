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

  /// Resamples the polyline ([px], [py]) with radii [pr] every [step]
  /// units of length, interpolating linearly; the final sample is the
  /// polyline's end (closer than [step] to its predecessor).
  ///
  /// The spacing is fixed rather than fitted to the total length, so the
  /// samples of a stroke being drawn stay where they are as it grows —
  /// otherwise every new input point would shift every sample and make the
  /// whole stroke shimmer.
  factory Centerline.resample(List<double> px, List<double> py, List<double> pr, double step) {
    final m = px.length;
    final x = <double>[px[0]], y = <double>[py[0]], r = <double>[pr[0]];
    var next = step; // arc length of the next sample
    var along = 0.0;
    for (var j = 0; j < m - 1 && step > 0; j++) {
      final seg = _dist(px[j + 1] - px[j], py[j + 1] - py[j]);
      while (next <= along + seg) {
        final t = seg == 0 ? 0.0 : (next - along) / seg;
        x.add(px[j] + (px[j + 1] - px[j]) * t);
        y.add(py[j] + (py[j + 1] - py[j]) * t);
        r.add(pr[j] + (pr[j + 1] - pr[j]) * t);
        next += step;
      }
      along += seg;
    }
    if (along == 0 || step <= 0) {
      return Centerline(
        Float64List.fromList([px[0]]),
        Float64List.fromList([py[0]]),
        Float64List.fromList([pr.reduce(math.max)]),
        0,
      );
    }
    if (along - (next - step) > step * 1e-3) {
      x.add(px[m - 1]);
      y.add(py[m - 1]);
      r.add(pr[m - 1]);
    }
    return Centerline(
      Float64List.fromList(x),
      Float64List.fromList(y),
      Float64List.fromList(r),
      step,
    );
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

  /// Smooths the radii with a one-sided (causal) exponential filter of
  /// length scale [scale]: each radius depends only on input *behind* it,
  /// so the width of ink already drawn never changes as the stroke grows
  /// (a symmetric filter would make the width behind the pen tip flicker).
  void smoothRadii(double scale) {
    if (step <= 0 || scale <= 0) return;
    // Two cascaded passes at half the scale: same overall reach, much
    // stronger suppression of sample-to-sample noise than a single pass.
    final keep = math.exp(-2 * step / scale);
    for (var pass = 0; pass < 2; pass++) {
      for (var i = 1; i < length; i++) {
        r[i] = r[i - 1] * keep + r[i] * (1 - keep);
      }
    }
  }

  /// Limits how fast the radius may change along the line to [slope]
  /// (radius units per unit of length), looking only backwards, so a
  /// pressure jump becomes a smooth swell and drawn ink stays put.
  void limitRadiusSlope(double slope) {
    final d = slope * step;
    for (var i = 1; i < length; i++) {
      r[i] = r[i].clamp(r[i - 1] - d, r[i - 1] + d);
    }
  }

  /// Makes the ends non-swelling: over the last [reach] of length at an end
  /// the radius may only stay level or shrink towards the tip, so pressure
  /// spikes at pen-down or pen-up can never become blobs.
  ///
  /// Pass `end: false` while a stroke is still being drawn: its moving end
  /// is not a real end yet, and settling it on every frame would make the
  /// width just behind the pen tip pulse as the stroke grows.
  void settleEnds(double reach, {bool start = true, bool end = true}) {
    final k = step == 0 ? 0 : math.min(length - 1, (reach / step).ceil());
    if (end) {
      for (var i = length - k; i < length; i++) {
        if (i > 0) r[i] = math.min(r[i], r[i - 1]);
      }
    }
    if (start) {
      for (var i = k - 1; i >= 0; i--) {
        if (i < length - 1) r[i] = math.min(r[i], r[i + 1]);
      }
    }
  }

  /// Removes the pressure ramp at the ends: real pen-down/pen-up pressure
  /// rises/falls over the first/last few samples, which would start and end
  /// every stroke thin — on handwriting, made of many short strokes, that
  /// reads as width flicker. Within [reach] of a levelled end the radius is
  /// raised to the radius found at [reach] (never above it, so this cannot
  /// create blobs). Tapers, when enabled, are applied afterwards.
  void levelEnds(double reach, {bool start = true, bool end = true}) {
    final k = step == 0 ? 0 : (reach / step).ceil();
    if (k == 0 || length < 2 * k + 1) return;
    if (start) {
      final level = r[k];
      for (var i = 0; i < k; i++) {
        r[i] = math.max(r[i], level);
      }
    }
    if (end) {
      final level = r[length - 1 - k];
      for (var i = length - k; i < length; i++) {
        r[i] = math.max(r[i], level);
      }
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
