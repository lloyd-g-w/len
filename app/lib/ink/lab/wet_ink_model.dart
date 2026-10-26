import 'dart:math' as math;
import 'dart:ui';

import '../input/pen_stabiliser.dart';
import '../input/stroke_sampler.dart';
import '../input/wet_ink.dart';
import '../render/growable.dart';
import '../render/hooks.dart';
import '../render/stroke_shaper.dart';
import '../render/taper.dart';
import 'wet_ink_ends.dart';
import 'wet_ink_segment.dart';

export 'wet_ink_segment.dart';

part 'wet_ink_radii.dart';
part 'wet_ink_segments.dart';

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
///  * **Stabiliser**: with [WetInkShape.stabiliser], each sample's position
///    is the [PenStabiliser]'s, as the input controller applies it; at
///    the lift the stroke stops where the ink is, short of the pen, as
///    Flutter's does.
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
class WetInkModel with _WetInkRadii, _WetInkSegments {
  WetInkModel({required this.radii, required this.shape, required this.frameMs})
    : _hooks = HookFinder.lengths(
        maxStart: shape.hookStart,
        maxEnd: shape.hookEnd,
        body: shape.hookBody,
        local: shape.hookLocal,
      ),
      _stabiliser = switch (shape.stabiliser) {
        final p? => PenStabiliser(p),
        null => null,
      };

  /// Radius (same units as positions) at pressures 0, 0.1, … 1.
  @override
  final List<double> radii;

  /// The geometry rules, in the units of the positions.
  @override
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
  @override
  final List<WetSample> samples = [];

  final HookFinder _hooks;
  final PenStabiliser? _stabiliser;

  // Every point of the contact (the hooks are decided on them), and how
  // many of them the pen-down hook drops, once decided.
  final DoubleBuffer _x = DoubleBuffer(), _y = DoubleBuffer();
  @override
  int? _start;

  // When the pen-down hook was trimmed (the time of the point that decided
  // it), and the largest radius among its points (a dot is as large as the
  // largest radius of the whole contact, as Flutter draws it).
  int? _trimmedAtMs;
  @override
  double _trimmedRadius = 0;

  // The end taper of the committed stroke (0 until [commit]).
  @override
  double _endTaper = 0;

  double _pressure = -1;
  Offset? _last;
  final List<WetSample> _dropped = [];
  @override
  bool _lifted = false;

  /// Adds a digitiser sample; [pressure] already normalised to 0..1.
  /// [lift] marks the pen-up sample.
  void add(Offset position, double pressure, int timeMs, {bool lift = false}) {
    if (_lifted) return;
    final s = _stabiliser;
    if (s != null) {
      // At the lift the pen has not moved since its last sample but for
      // Flutter's synthesized move there (the up's own position).
      if (lift && position == s.pen) {
        _updatePressure(pressure, lift: true);
        return _lift(timeMs);
      }
      position = s.add(position);
    }
    _updatePressure(pressure, lift: lift);
    _thin(WetSample(position, _pressure, timeMs));
    if (lift) _lift(timeMs);
  }

  void _updatePressure(double pressure, {required bool lift}) {
    final norm = StrokeSampler.strokePressure(pressure);
    if (!lift || _pressure < 0) {
      _pressure = _pressure < 0
          ? norm
          : _pressure * shape.pressureKeep + norm * (1 - shape.pressureKeep);
    }
  }

  /// Keeps [sample] as a point, or drops it as too close (see the class
  /// documentation, *Points*).
  void _thin(WetSample sample) {
    final position = sample.position;
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
  /// rules, and the sample round ends stop short of the final line
  /// (`StrokeOutline.shownOf`).
  double get _lagReach {
    final p = shape;
    return (p.kernel.length ~/ 2 + p.cornerK + p.lag + (p.flat ? 2 : 3)) * p.step;
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

  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final l2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (l2 == 0) return (p - a).distance;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / l2).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }
}
