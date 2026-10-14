part of 'wet_ink_model.dart';

/// The overlay's pieces: the smoothed, tapered line between two points.
mixin _WetInkSegments on _WetInkRadii {
  bool get _lifted;
  int? get _start;
  double get _trimmedRadius;
  double get _endTaper;

  // Spline length from the first point to point i (as the outline's
  // resampling measures it), for the points so far.
  final List<double> _arcs = [0];

  /// The overlay's pieces from point [from] to [to] (exclusive): the hull
  /// of the circles `(a, ra)` and `(b, rb)` of consecutive smoothed points;
  /// one point is a dot (a == b).
  List<WetSegment> segments(int from, int to) {
    final r = pointRadii();
    final flat = shape.flat;
    if (to - from == 1) {
      final s = samples[from];
      final whole = from == 0 && to == samples.length;
      final last = _lifted && to == samples.length;
      final radius = whole
          ? math.max(r[from], _trimmedRadius)
          : r[from] *
                Taper.factor(_arc[from], shape.taperStart) *
                (last && _endTaper > 0 ? Taper.minFactor : 1);
      return [WetSegment(s.position, s.position, radius, radius, flatA: flat, flatB: flat)];
    }
    // Smooth from a little before [from]: the kernel, its end fit and the
    // corner test reach that far back.
    final p = shape.positions;
    final reach = (p.kernelK + p.fit + p.cornerK + 4) * p.step;
    var start = from;
    var back = 0.0;
    while (start > 0 && back < reach) {
      back += (samples[start].position - samples[start - 1].position).distance;
      start--;
    }
    // Resample in step with the whole line: from the spline length up to
    // the window's first point, with the point before it as the spline's
    // lead-in.
    final StrokeShaper shaper;
    // Arc length from the start of the window's first resampled point and
    // of its second (the others follow a step apart), for the tapers.
    var arc0 = 0.0, arc1 = p.step;
    if (start == 0) {
      shaper = StrokeShaper(p);
    } else {
      final arc = _splineArc(start, p.step);
      final phase = (arc / p.step).ceil() * p.step - arc;
      shaper = StrokeShaper(p, start: 1, phase: phase);
      arc0 = arc;
      arc1 = arc + (phase > 1e-9 ? phase : p.step);
    }
    for (var i = math.max(0, start - 1); i < to; i++) {
      final s = samples[i].position;
      shaper.add(s.dx, s.dy, r[i]);
    }
    final ended = _lifted && to == samples.length;
    shaper.update(ended: ended);
    // A line shorter than half its width is a dot, as Flutter draws it
    // (`StrokeOutline.isDot`): the largest radius, at the first point.
    if (start == 0 && to == samples.length && _isDot(shaper)) {
      var r = _trimmedRadius;
      for (final s in samples) {
        r = math.max(r, radiusAt(s.pressure));
      }
      final c = samples[0].position;
      return [WetSegment(c, c, r, r, flatA: flat, flatB: flat)];
    }
    // The smoothed points from about where point [from] is.
    var skip = 0.0;
    for (var i = start + 1; i <= from; i++) {
      skip += (samples[i].position - samples[i - 1].position).distance;
    }
    final first = math.max(0, (skip / p.step).floor() - 1);
    final x = shaper.x, y = shaper.y;
    final rr = _tapered(shaper, arc0, arc1, ended: ended);
    // With the stabiliser on, as far as Flutter's live ink reaches (its
    // final line); from pen-down until the hook is decided, its first point.
    final n = shape.lag == 0 || ended
        ? shaper.length
        : _start == null
        ? 1
        : math.max(1, shaper.finalCount);
    if (n - first < 2) {
      final i = math.min(first, n - 1);
      final c = Offset(x[i], y[i]);
      return [WetSegment(c, c, rr[i], rr[i], flatA: flat, flatB: flat)];
    }
    // Flat ends: the stroke's start, if drawn, and the drawn end.
    final ends = flat
        ? WetInkEnds.of(
            x,
            y,
            rr,
            shaper.corners,
            n,
            first: first,
            step: p.step,
            start: start == 0,
            reach: shape.flatReach,
          )
        : null;
    return [
      for (var i = first + 1; i < n; i++)
        WetSegment(
          Offset(x[i - 1], y[i - 1]),
          Offset(x[i], y[i]),
          rr[i - 1],
          rr[i],
          flatA: flat && start == 0 && i == 1,
          flatB: flat && i == n - 1,
          cuts: [
            for (final c in ends?.cuts ?? const <WetCut>[])
              if (c.piece == i - 1) c.line,
          ],
          sweeps: [
            for (final w in ends?.sweeps ?? const <WetSweep>[])
              if (w.piece == i - 1) (w.a, w.b),
          ],
        ),
    ];
  }

  /// The radii of [shaper]'s points with the tapers: the start's by arc
  /// length from the start (the first point at [arc0], the second at
  /// [arc1], then a step apart), once [ended] and committed the end's.
  List<double> _tapered(StrokeShaper shaper, double arc0, double arc1, {required bool ended}) {
    final n = shaper.length, step = shaper.p.step;
    final r = [for (var i = 0; i < n; i++) shaper.r[i]];
    double arcOf(int i) => i == 0 ? arc0 : arc1 + (i - 1) * step;
    if (shape.taperStart > 0) {
      for (var i = 0; i < n; i++) {
        r[i] *= Taper.factor(arcOf(i), shape.taperStart);
      }
    }
    if (ended && _endTaper > 0 && n > 1 && samples.length > 1) {
      final total = _splineArc(samples.length - 1, step);
      final length = math.min(_endTaper, total * Taper.maxEndShare);
      for (var i = n - 1; i >= 0; i--) {
        final along = i == n - 1 ? 0.0 : total - arcOf(i);
        if (along >= length) break;
        r[i] *= Taper.factor(along, length);
      }
    }
    return r;
  }

  /// `StrokeOutline.isDot` for the whole line in [s].
  static bool _isDot(StrokeShaper s) {
    if (s.length < 2) return true;
    var maxR = 0.0;
    for (var i = 0; i < s.length; i++) {
      maxR = math.max(maxR, s.r[i]);
    }
    return s.p.step * (s.length - 1) < maxR * 0.5;
  }

  double _splineArc(int i, double step) {
    while (_arcs.length <= i) {
      final k = _arcs.length - 1; // segment k → k + 1
      Offset at(int j) => samples[j].position;
      final a = at(k), b = at(k + 1);
      final before = k > 0 ? at(k - 1) : a * 2 - b;
      final after = k + 2 < samples.length ? at(k + 2) : b * 2 - a;
      _arcs.add(
        _arcs[k] +
            StrokeShaper.segmentLength(
              before.dx,
              before.dy,
              a.dx,
              a.dy,
              b.dx,
              b.dy,
              after.dx,
              after.dy,
              step,
            ),
      );
    }
    return _arcs[i];
  }
}
