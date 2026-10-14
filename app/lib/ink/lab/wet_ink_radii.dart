part of 'wet_ink_model.dart';

/// The radius of every point: the pressure table, causal smoothing by
/// length, then the start and tip rules.
mixin _WetInkRadii {
  List<double> get radii;
  WetInkShape get shape;
  List<WetSample> get samples;

  // Causal radii per point (two passes, slope-limited) and arc lengths.
  final List<double> _r1 = [], _r2 = [], _rs = [], _arc = [];

  void _forget(int from) {
    for (final l in [_r1, _r2, _rs, _arc]) {
      if (l.length > from) l.removeRange(math.max(0, from), l.length);
    }
  }

  double radiusAt(double p) {
    if (radii.length == 1) return radii[0];
    final t = p.clamp(0.0, 1.0) * (radii.length - 1);
    final i = math.min(t.floor(), radii.length - 2);
    return radii[i] + (radii[i + 1] - radii[i]) * (t - i);
  }

  /// The radius of every point: causal smoothing by length, then the start
  /// and tip rules.
  List<double> pointRadii() {
    final n = samples.length;
    // The causal part, cached (it depends only on the points before).
    for (var i = _rs.length; i < n; i++) {
      final raw = radiusAt(samples[i].pressure);
      if (i == 0) {
        _r1.add(raw);
        _r2.add(raw);
        _rs.add(raw);
        _arc.add(0);
        continue;
      }
      final d = (samples[i].position - samples[i - 1].position).distance;
      _arc.add(_arc[i - 1] + d);
      // In steps along the segment, the input radius interpolated (as the
      // outline filters its resampled line).
      final before = radiusAt(samples[i - 1].pressure);
      final steps = math.max(1, (d / shape.step).ceil());
      final h = d / steps;
      final keep = math.exp(-2 * h / shape.radiusSigma);
      var r1 = _r1[i - 1], r2 = _r2[i - 1], limited = _rs[i - 1];
      for (var k = 1; k <= steps; k++) {
        final input = before + (raw - before) * k / steps;
        r1 = r1 * keep + input * (1 - keep);
        r2 = r2 * keep + r1 * (1 - keep);
        limited = r2.clamp(limited - shape.slope * h, limited + shape.slope * h);
      }
      _r1.add(r1);
      _r2.add(r2);
      _rs.add(limited);
    }
    final r = List<double>.of(_rs);
    final arc = _arc;
    if (n == 0) return r;
    final total = arc[n - 1];
    for (var i = n - 2; i >= 0; i--) {
      if (arc[i] < shape.settleStart) r[i] = math.min(r[i], r[i + 1]);
    }
    _level(r, arc, (i) => arc[i], shape.levelStart);
    for (var i = 1; i < n; i++) {
      if (total - arc[i] < shape.settleEnd) r[i] = math.min(r[i], r[i - 1]);
    }
    _level(r, arc, (i) => total - arc[i], shape.levelEnd);
    return r;
  }

  /// Raises the radius within [reach] of an end (distance [fromEnd]) to the
  /// radius found at [reach].
  static void _level(List<double> r, List<double> arc, double Function(int) fromEnd, double reach) {
    if (reach <= 0 || arc.isEmpty || arc.last < 2 * reach) return;
    var level = -1.0;
    var best = double.infinity;
    for (var i = 0; i < r.length; i++) {
      final d = (fromEnd(i) - reach).abs();
      if (fromEnd(i) >= reach && d < best) {
        best = d;
        level = r[i];
      }
    }
    if (level < 0) return;
    for (var i = 0; i < r.length; i++) {
      if (fromEnd(i) < reach) r[i] = math.max(r[i], level);
    }
  }
}
