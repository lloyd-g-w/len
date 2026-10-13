import 'dart:math' as math;
import 'dart:ui';

import '../input/stroke_sampler.dart';
import '../input/wet_ink.dart';
import '../render/flat_ends.dart';
import '../render/growable.dart';
import '../render/hooks.dart';
import '../render/stroke_shaper.dart';
import '../render/taper.dart';
import 'wet_ink_ends.dart';

/// A Dart model of what the experimental low-latency overlay
/// (`android/.../WetInkOverlay.kt`) draws, so its geometry and timing can
/// be checked against Flutter's ink without a device. The Kotlin code
/// follows it step by step:
///
///  * **Samples**: every digitiser sample of the contact (historical and
///    current), position in view pixels, time in whole milliseconds
///    (`MotionEvent` times), pressure normalised by the device's range,
///    clamped to 0.05..1, through the `PressureCurve` and smoothed by the
///    same filter as Dart's `PressureFilter` (the lift sample keeps the
///    previous pressure, as Flutter's synthesized up move does).
///  * **Points**: thinned like the input controller does (`PointSpacing`):
///    closer than [WetInkShape.minSpacing] to the last point is dropped,
///    unless it is the furthest dropped sample and more than
///    [WetInkShape.keepExtreme] off the line to the next point.
///  * **Pen-down hook**: decided with the outline's rules ([HookFinder]
///    with [WetInkShape.hookStart]) as soon as the points reach far enough,
///    exactly when Flutter's outline decides it; until then every point is
///    drawn (as Flutter shows the stroke from pen-down), then the hook's
///    points are dropped.
///  * **Radius**: the `begin` radius table (pressure 0, 0.1 … 1), then the
///    outline's causal smoothing by length (two exponential passes and a
///    slope limit, in steps of [WetInkShape.step] along each segment, like
///    the outline's resampled line), the non-swelling and levelled start,
///    and the same rules at the tip (so the overlay's tip is as wide as
///    Flutter's will be).
///  * **Positions**: the outline's position rules ([WetInkShape.positions]:
///    resampling every step along a Catmull-Rom spline, corners, the
///    low-pass kernel with its end fit) applied to the points from a little
///    before the tail (enough for the kernel), so the overlay's ink lies
///    where Flutter's will, also with the stabiliser up.
///  * **Lift**: the last three pressures may not rise, and the pen-up hook
///    is trimmed with the outline's rules ([HookFinder]; the pen-down hook
///    is decided now if it was not yet).
///  * **Shape**: the hull of the circles of consecutive smoothed points (a
///    capsule of two circles, of their own radii, and the quad between their
///    tangents);
///    one point is a dot, and so is a whole line shorter than half its
///    width, with the contact's largest radius (as Flutter draws it).
///  * **Ends**: with [WetInkShape.flat], the stroke's start and the drawn
///    end are butt caps (a lone point a square, as Flutter's flat dot),
///    square to the line as Flutter's are, with the pieces next to them
///    cut off at the cap's line, also at the moving pen tip ([WetInkEnds]); a
///    start taper ([WetInkShape.taperStart]) scales the smoothed points'
///    radii by their arc length from the start (`Taper.factor`), and once
///    Flutter has committed the stroke ([commit]) the end taper it was
///    committed with does the same from the end. Not at the lift: Flutter's
///    live frames built before the lift, still to be shown, draw the end
///    untapered, so a taper drawn sooner would show, vanish under them and
///    show again.
///  * **Tail**: on every commit (after each Flutter frame's `progress`,
///    and every frame while a tail remains) the front buffer is cleared
///    and only points newer than the `progress` reported two messages
///    before the latest are drawn (Flutter presents a frame about two
///    frames after building it; counting messages rather than time keeps
///    this right when frames are late), plus the point before them (the
///    segment leading in; with the stabiliser on, from where Flutter's ink
///    ends, and with flat ends from before its end's zone); after the lift
///    at least the last point; and
///    every point while Flutter's frame still shows a pen-down hook the
///    model has trimmed (so the start Flutter will show is drawn). New
///    points are drawn into the front buffer as they arrive. After `end`,
///    the tail stays until [endFrames] frames have passed.
class WetInkModel {
  WetInkModel({required this.radii, required this.shape, required this.frameMs})
    : _hooks = HookFinder.lengths(
        maxStart: shape.hookStart,
        maxEnd: shape.hookEnd,
        body: shape.hookBody,
        local: shape.hookLocal,
      );

  /// Radius (same units as positions) at pressures 0, 0.1, … 1.
  final List<double> radii;

  /// The geometry rules, in the units of the positions.
  final WetInkShape shape;

  /// Display frame interval.
  final double frameMs;

  /// How many `progress` messages before the latest one the overlay takes
  /// as what Flutter shows (frames are presented that many frames after
  /// they are built, at most).
  static const int progressLag = 2;

  /// Frames the tail stays after `end` (sent once the frame showing the
  /// committed stroke is built): enough for a pipeline one frame deeper
  /// than [progressLag] (the overlay's ink is the committed ink, so staying
  /// longer costs nothing).
  static const int endFrames = 3;

  /// The points drawn: from the end of the pen-down hook, or from pen-down
  /// while that is undecided.
  final List<WetSample> samples = [];

  final HookFinder _hooks;

  // Every point of the contact (the hooks are decided on them), and how
  // many of them the pen-down hook drops, once decided.
  final DoubleBuffer _x = DoubleBuffer(), _y = DoubleBuffer();
  int? _start;

  // When the pen-down hook was trimmed (the time of the point that decided
  // it), and the largest radius among its points (a dot is as large as the
  // largest radius of the whole contact, as Flutter draws it).
  int? _trimmedAtMs;
  double _trimmedRadius = 0;

  // The end taper of the committed stroke (0 until [commit]).
  double _endTaper = 0;

  double _pressure = -1;
  Offset? _last;
  final List<WetSample> _dropped = [];
  bool _lifted = false;

  /// Adds a digitiser sample; [pressure] already normalised to 0..1.
  /// [lift] marks the pen-up sample.
  void add(Offset position, double pressure, int timeMs, {bool lift = false}) {
    if (_lifted) return;
    final norm = StrokeSampler.strokePressure(pressure);
    if (!lift || _pressure < 0) {
      _pressure = _pressure < 0
          ? norm
          : _pressure * shape.pressureKeep + norm * (1 - shape.pressureKeep);
    }
    final sample = WetSample(position, _pressure, timeMs);
    final last = _last;
    if (last == null) {
      _keep(sample);
    } else if ((position - last).distance < shape.minSpacing) {
      _dropped.add(sample);
    } else {
      WetSample? extreme;
      var best = shape.keepExtreme;
      for (final d in _dropped) {
        final off = _distanceToSegment(d.position, last, position);
        if (off > best) {
          best = off;
          extreme = d;
        }
      }
      _dropped.clear();
      if (extreme != null) _keep(extreme);
      _keep(sample);
    }
    if (lift) _lift(timeMs);
  }

  void _keep(WetSample s) {
    _last = s.position;
    _x.add(s.position.dx);
    _y.add(s.position.dy);
    samples.add(s);
    if (_start == null) _decideStart(_x.length, ended: false, atMs: s.timeMs);
  }

  /// Decides the pen-down hook from the first [n] points, if they reach far
  /// enough (or the stroke [ended]), and drops its points.
  void _decideStart(int n, {required bool ended, required int atMs}) {
    final cut = _hooks.startCut(_x, _y, n, ended: ended);
    if (cut == null) return;
    _start = cut;
    if (cut == 0) return;
    _trimmedAtMs = atMs;
    for (var i = 0; i < math.min(cut, samples.length); i++) {
      _trimmedRadius = math.max(_trimmedRadius, radiusAt(samples[i].pressure));
    }
    samples.removeRange(0, math.min(cut, samples.length));
    _forget(0);
    _arcs
      ..clear()
      ..add(0);
  }

  // Causal radii per point (two passes, slope-limited) and arc lengths.
  final List<double> _r1 = [], _r2 = [], _rs = [], _arc = [];

  void _forget(int from) {
    for (final l in [_r1, _r2, _rs, _arc]) {
      if (l.length > from) l.removeRange(math.max(0, from), l.length);
    }
  }

  /// Pen-up: the last pressures may not rise; the pen-up hook is trimmed.
  void _lift(int timeMs) {
    _lifted = true;
    final n = samples.length;
    _forget(n - 3);
    final from = math.max(1, n - 3);
    for (var i = from; i < n; i++) {
      final ceiling = samples[i - 1].pressure;
      if (samples[i].pressure > ceiling) {
        final s = samples[i];
        samples[i] = WetSample(s.position, ceiling, s.timeMs);
      }
    }
    // The pen-up hook, on every point (as the outline finds it).
    final all = _x.length;
    final keepAll = all < 2 ? all : _hooks.endKeep(_x, _y, all);
    if (_start == null) _decideStart(keepAll, ended: true, atMs: timeMs);
    final keep = math.max(math.min(1, samples.length), keepAll - _start!);
    samples.removeRange(keep, samples.length);
    _forget(keep);
    // Spline lengths that used a removed point.
    if (_arcs.length > keep - 1) _arcs.removeRange(math.max(1, keep - 1), _arcs.length);
  }

  /// Flutter has committed the stroke (the overlay's `end`), with an end
  /// taper [taperEnd] long (0: none; in the units of the positions).
  void commit({double taperEnd = 0}) => _endTaper = taperEnd;

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

  /// Index of the first point the overlay shows at [nowMs], given the
  /// `progress` reported two messages before the latest ([shownUpToMs]: the
  /// input of the frame Flutter shows, at the latest) and, after `end`,
  /// when it ended. Equal to the number of points when it shows nothing.
  int tailStart({required double nowMs, required double shownUpToMs, double? endedAtMs}) {
    if (endedAtMs != null && nowMs - endedAtMs >= endFrames * frameMs) return samples.length;
    final cutoff = shownUpToMs;
    var from = samples.length;
    while (from > 0 && samples[from - 1].timeMs > cutoff) {
      from--;
    }
    // After the lift Flutter's last live frame may still be on screen while
    // the committed end (pen-up hook trimmed, end settled) differs from it:
    // keep the last point until the committed stroke is shown.
    if (_lifted && samples.isNotEmpty) from = math.min(from, samples.length - 1);
    // Flutter's frame still shows the start from pen-down (the hook it has
    // not trimmed yet): draw the start as it is now, from its first point.
    final trimmed = _trimmedAtMs;
    if (trimmed != null && trimmed > cutoff && samples.isNotEmpty) return 0;
    if (from == samples.length) return from;
    from = math.max(0, from - 1);
    // With the stabiliser on, Flutter's ink ends further back than its
    // newest input (as far as the line was final then); with flat ends, its
    // end's zone, cut off at the cap and swept by a flat nib, has less ink
    // than the line will have there once it goes on: draw from before them.
    final reach = (shape.lag > 0 ? _lagReach : 0.0) + (shape.flat ? _flatReach : 0.0);
    if (reach > 0) from = _back(from, reach);
    return from;
  }

  /// How far (arc length) a flat end's zone reaches at most: two widths.
  double get _flatReach => shape.flatReach * shape.step;

  /// How far (arc length) behind its newest input Flutter's live ink ends
  /// at most with the stabiliser on: the resampling's last final segments
  /// (three points, see [_back]), the corner test, the kernel and the tip
  /// rules.
  double get _lagReach {
    final p = shape;
    return (p.kernel.length ~/ 2 + p.cornerK + p.lag + 2) * p.step;
  }

  /// The point [reach] (arc length) and three more points before point [i].
  int _back(int i, double reach) {
    var at = math.max(0, i - 3);
    var back = 0.0;
    while (at > 0 && back < reach) {
      back += (samples[at].position - samples[at - 1].position).distance;
      at--;
    }
    return at;
  }

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

  // Spline length from the first point to point i (as the outline's
  // resampling measures it), for the points so far.
  final List<double> _arcs = [0];

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

  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final l2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (l2 == 0) return (p - a).distance;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / l2).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }
}

/// A sample as the overlay keeps it.
class WetSample {
  const WetSample(this.position, this.pressure, this.timeMs);
  final Offset position;
  final double pressure;
  final int timeMs;
}

/// One piece the overlay draws: the hull of two circles.
class WetSegment {
  const WetSegment(
    this.a,
    this.b,
    this.ra,
    this.rb, {
    this.flatA = false,
    this.flatB = false,
    this.cuts = const [],
    this.sweeps = const [],
  });
  final Offset a, b;
  final double ra, rb;

  /// A butt cap at [a] / [b] (the stroke's start, the drawn end); a dot
  /// (a == b) with both is a square.
  final bool flatA, flatB;

  /// The lines of the flat ends' butt caps this piece is cut off at
  /// (`WetInkEnds`): what lies beyond one, on the side its normal faces,
  /// is not drawn.
  final List<EndLine> cuts;

  /// Within a flat end's zone, the piece is the area a flat nib sweeps
  /// between these cross-sections (`emitSweep`), not the hull of its
  /// circles; then cut off at [cuts].
  final List<(CrossSection, CrossSection)> sweeps;
}
