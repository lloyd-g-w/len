import 'dart:math' as math;
import 'dart:ui';

import '../input/wet_ink.dart';
import '../render/growable.dart';
import '../render/hooks.dart';

/// A Dart model of what the experimental low-latency overlay
/// (`android/.../WetInkOverlay.kt`) draws, so its geometry and timing can
/// be checked against Flutter's ink without a device. The Kotlin code
/// follows it step by step:
///
///  * **Samples**: every digitiser sample of the contact (historical and
///    current), position in view pixels, time in whole milliseconds
///    (`MotionEvent` times), pressure normalised by the device's range,
///    clamped to 0.05..1 and smoothed by the same filter as Dart's
///    `PressureFilter` (the lift sample keeps the previous pressure, as
///    Flutter's synthesized up move does).
///  * **Points**: thinned like the input controller does (`PointSpacing`):
///    closer than [WetInkShape.minSpacing] to the last point is dropped,
///    unless it is the furthest dropped sample and more than
///    [WetInkShape.keepExtreme] off the line to the next point. Points
///    before `startMs` (the pen-down hook Flutter trims, sent with `begin`)
///    are not drawn.
///  * **Radius**: the `begin` radius table (pressure 0, 0.1 … 1), then the
///    outline's causal smoothing by length (two exponential passes and a
///    slope limit), the non-swelling and levelled start, and the same rules
///    at the tip (so the overlay's tip is as wide as Flutter's will be).
///  * **Lift**: the last three pressures may not rise, and the pen-up hook
///    is trimmed with the outline's rules ([HookFinder]).
///  * **Shape**: the hull of the circles of consecutive points (a tapered
///    capsule: two circles and the quad between their tangents); one point
///    is a dot.
///  * **Tail**: on every commit (after each Flutter frame's `progress`,
///    and every frame while a tail remains) the front buffer is cleared
///    and only points newer than `max(progress − 2 frames, now − 5
///    frames)` are drawn, plus the point before them (the segment leading
///    in). New points are drawn into the front buffer as they arrive.
///    After `end`, the tail stays until 2 frames have passed.
class WetInkModel {
  WetInkModel({required this.radii, required this.shape, required this.frameMs, this.startMs = 0});

  /// Radius (same units as positions) at pressures 0, 0.1, … 1.
  final List<double> radii;

  /// The geometry rules, in the units of the positions.
  final WetInkShape shape;

  /// Display frame interval.
  final double frameMs;

  /// Points before this time are not ink (the pen-down hook).
  final int startMs;

  /// The points drawn (from `startMs` on).
  final List<WetSample> samples = [];

  double _pressure = -1;
  Offset? _last;
  final List<WetSample> _dropped = [];
  bool _lifted = false;

  /// Adds a digitiser sample; [pressure] already normalised to 0..1.
  /// [lift] marks the pen-up sample.
  void add(Offset position, double pressure, int timeMs, {bool lift = false}) {
    if (_lifted) return;
    final norm = pressure.clamp(0.05, 1.0);
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
    if (lift) _lift();
  }

  void _keep(WetSample s) {
    _last = s.position;
    if (s.timeMs >= startMs) samples.add(s);
  }

  /// Pen-up: the last pressures may not rise; the pen-up hook is trimmed.
  void _lift() {
    _lifted = true;
    final n = samples.length;
    final from = math.max(1, n - 3);
    for (var i = from; i < n; i++) {
      final ceiling = samples[i - 1].pressure;
      if (samples[i].pressure > ceiling) {
        final s = samples[i];
        samples[i] = WetSample(s.position, ceiling, s.timeMs);
      }
    }
    final x = DoubleBuffer(), y = DoubleBuffer();
    for (final s in samples) {
      x.add(s.position.dx);
      y.add(s.position.dy);
    }
    final hooks = HookFinder.lengths(
      maxStart: 0,
      maxEnd: shape.hookEnd,
      body: shape.hookBody,
      local: shape.hookLocal,
    );
    final keep = samples.length < 2 ? samples.length : hooks.endKeep(x, y, samples.length);
    samples.removeRange(keep, samples.length);
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
    final r = List<double>.filled(n, 0);
    final arc = List<double>.filled(n, 0);
    double r1 = 0, r2 = 0;
    for (var i = 0; i < n; i++) {
      final raw = radiusAt(samples[i].pressure);
      if (i == 0) {
        r1 = r2 = r[0] = raw;
        continue;
      }
      final d = (samples[i].position - samples[i - 1].position).distance;
      arc[i] = arc[i - 1] + d;
      final keep = math.exp(-2 * d / shape.radiusSigma);
      r1 = r1 * keep + raw * (1 - keep);
      r2 = r2 * keep + r1 * (1 - keep);
      r[i] = r2.clamp(r[i - 1] - shape.slope * d, r[i - 1] + shape.slope * d);
    }
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
  /// newest `progress` ([flutterUpToMs]) and, after `end`, when it ended.
  /// Equal to the number of points when it shows nothing.
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

  /// The overlay's pieces from point [from] to [to] (exclusive): the hull
  /// of the circles `(a, ra)` and `(b, rb)`; one point is a dot (a == b).
  List<WetSegment> segments(int from, int to) {
    final r = pointRadii();
    if (to - from == 1) {
      final s = samples[from];
      return [WetSegment(s.position, s.position, r[from], r[from])];
    }
    return [
      for (var i = from + 1; i < to; i++)
        WetSegment(samples[i - 1].position, samples[i].position, r[i - 1], r[i]),
    ];
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
  const WetSegment(this.a, this.b, this.ra, this.rb);
  final Offset a, b;
  final double ra, rb;
}
