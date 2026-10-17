import 'dart:math' as math;
import 'dart:typed_data';

import 'growable.dart';
import 'hooks.dart';
import 'line_filters.dart';
import 'ribbon_emitter.dart';
import 'shape_params.dart';
import 'taper.dart';

part 'stroke_shaper_checkpoints.dart';
part 'stroke_shaper_radii.dart';
part 'stroke_shaper_resampling.dart';
part 'stroke_shaper_samples.dart';
part 'stroke_shaper_smoothing.dart';

/// Turns the input points of a stroke into its smoothed centre line with
/// radii, *incrementally* and with a fixed reach: every value further than
/// a fixed distance behind the pen tip is **final** — computed once, from
/// input that can no longer change, and bit-identical in every later frame
/// and in the committed stroke.
///
/// Stages (each one only looks a fixed number of samples ahead):
///  1. dedupe: points closer than a hair are merged (positions never move
///     afterwards; only the last radius may still grow);
///  2. pen-down hook: decided once from the first few screen px
///     ([HookFinder.decisionLength]); until then the line is *provisional*:
///     it starts at the first sample and nothing of it is final, so the
///     stroke shows from pen-down and its start changes at most once, when
///     a hook is trimmed;
///  3. resampling every [ShapeParams.step] along a centripetal Catmull-Rom
///     spline through the samples, from the stroke's start (a segment is
///     final once the sample after its end is);
///  4. corners: where the line doubles back within a short baseline; the
///     tip of each such spot, the sample furthest along the direction the
///     line came in from (final once the spot has passed);
///  5. positions: the finite low-pass kernel of [LineFilters.lowPassKernel]
///     per stretch between corners, each stretch continued beyond its ends
///     by a local quadratic fit (no lag, tips stay put);
///  6. radii: causal (two cascaded exponential passes, then a slope limit),
///     so final as soon as their sample is; then the end rules, which only
///     touch the first and last few samples; then the tapers: the start's
///     ([ShapeParams.taperStart]) by arc length from the start, so final
///     with its sample, and once the stroke has ended the end's
///     ([taperEnd]).
///
/// [line] writes the whole line (final values plus the not-yet-final tail)
/// into the output buffers; only the tail is recomputed per call.
class StrokeShaper with _SampleIndex implements RibbonLine {
  /// A shaper for [p]. For a piece of a longer line (the low-latency
  /// overlay smooths only the newest part), [start] makes input sample
  /// `start − 1` a lead-in (only the spline's neighbour of the first
  /// segment) and [phase] is the arc length of the first resampled point
  /// after the start, so the samples fall where the whole line's do.
  StrokeShaper(this.p, {int? start, double? phase})
    : _hooks = p.hooks,
      _start = start,
      _leadIn = start != null && start > 0,
      _phase = phase; // ignore: prefer_initializing_formals

  final ShapeParams p;
  final HookFinder _hooks;

  // 1. Deduplicated input samples (position, radius).
  final DoubleBuffer _sx = DoubleBuffer(), _sy = DoubleBuffer(), _sr = DoubleBuffer();

  // 2. First sample kept (pen-down hook), once decided. While undecided,
  //    the line is computed from sample 0 and thrown away by the next
  //    [update] ([_provisional]).
  int? _start;
  bool _provisional = false;
  final bool _leadIn;
  final double? _phase;

  // 3. Resampled positions and interpolated input radii. [_resFinal] values
  //    are final; segments before [_seg] are done; [_next] is the arc
  //    length of the next sample from the start of segment [_seg].
  final DoubleBuffer _rx = DoubleBuffer(), _ry = DoubleBuffer(), _rr = DoubleBuffer();
  int _resFinal = 0;
  int _seg = 0;
  double _next = 0;

  // 6a. Causal radii: two exponential passes and the slope limit.
  final DoubleBuffer _r1 = DoubleBuffer(), _r2 = DoubleBuffer(), _rs = DoubleBuffer();
  int _radDone = 0;

  // 4. Corners: final ones, and the scan state after [_scan] (next index).
  final List<int> _corners = [];
  int _scan = 0;
  // The current run of sharp turns: its first sample, and its tip so far
  // (the sample furthest along the direction the line came in from).
  int _runFirst = -1;
  int _runBest = -1;
  double _runScore = 0;

  // 5. Smoothed positions; [_posFinal] of them final.
  final DoubleBuffer _cx = DoubleBuffer(), _cy = DoubleBuffer();
  int _posFinal = 0;

  // 6b. Output radii (end rules applied); [_roDone] of them final.
  final DoubleBuffer _ro = DoubleBuffer();
  int _roDone = 0;

  // 6c. Tapered radii (only with a taper): [_rtFrom] of them up to date.
  final DoubleBuffer _rt = DoubleBuffer();
  int _rtFrom = 0;

  /// Length (world units) over which the end narrows to a point once the
  /// stroke has ended (`OutlineSpec.taperEnd`; 0: none). Set before the
  /// [update] with `ended`.
  double taperEnd = 0;

  bool get _tapers => p.taperStart > 0 || taperEnd > 0;

  /// The first sample the end taper changed in the last [update] ([length]
  /// without one).
  int taperedFrom = 0;

  /// Corner sample indices of the last [update] (final and provisional).
  @override
  List<int> corners = const [];

  /// Number of samples of the last [update].
  @override
  int length = 0;

  /// Samples of the last [update] that are final (position and radius).
  int finalCount = 0;

  bool _ended = false;

  /// The samples live ink shows: all of them, or with the stabiliser on
  /// ([ShapeParams.lag]) only the final ones ([finalCount]: positions and
  /// radii; at least the first sample, so ink shows from pen-down), and all
  /// of them once the stroke has ended.
  int get liveLength {
    if (p.lag == 0 || _ended || length == 0) return length;
    return math.max(1, finalCount);
  }

  /// Whether the pen-down decision has been made (otherwise the line is
  /// provisional: from the first sample, nothing final).
  bool get started => _start != null;

  /// The first input sample kept (after the pen-down hook); 0 until
  /// [started].
  @override
  int get startSample => _start ?? 0;

  @override
  DoubleBuffer get x => _cx;
  @override
  DoubleBuffer get y => _cy;
  @override
  DoubleBuffer get r => _tapers ? _rt : _ro;

  /// The radii without the tapers (whether a line is a dot does not
  /// depend on them).
  DoubleBuffer get untaperedR => _ro;

  int get inputCount => _sx.length;

  /// The resampled, unsmoothed positions (for measurements).
  DoubleBuffer get rawX => _rx;
  DoubleBuffer get rawY => _ry;
  double inputX(int i) => _sx[i];
  double inputY(int i) => _sy[i];

  /// The outline radius input sample [i] was added with (the largest of
  /// the points merged into it).
  double inputR(int i) => _sr[i];

  /// The largest input radius (a dot's size).
  double get maxInputRadius {
    var m = 0.0;
    for (var i = 0; i < _sr.length; i++) {
      m = math.max(m, _sr[i]);
    }
    return m;
  }

  /// Number of input points [add]ed so far.
  @override
  int pointCount = 0;

  /// Adds an input point at ([x], [y]) with outline radius [radius].
  void add(double x, double y, double radius) {
    pointCount++;
    final n = _sx.length;
    if (n > 0) {
      final dx = x - _sx[n - 1], dy = y - _sy[n - 1];
      if (dx * dx + dy * dy < p.dedupe * p.dedupe) {
        _sr[n - 1] = math.max(_sr[n - 1], radius);
        return;
      }
    }
    _samplePoint.add(pointCount - 1);
    _sx.add(x);
    _sy.add(y);
    _sr.add(radius);
  }

  // ---------------------------------------------------------------------------
  // Checkpoints: the final state after recent [update]s, so the end of a
  // finished stroke (pen-up hook, settled pressures) can be redone without
  // starting over.

  final List<_Checkpoint> _checkpoints = [];
  static const int _keptCheckpoints = 48;

  /// Records the current final state; returns its id for [rollBack].
  int checkpoint() {
    _checkpoints.add(_Checkpoint.of(this, _checkpointIds++));
    if (_checkpoints.length > _keptCheckpoints) _checkpoints.removeAt(0);
    return _checkpoints.last.id;
  }

  int _checkpointIds = 0;

  /// Restores the latest checkpoint whose final values do not depend on
  /// input samples from [sample] on, and drops those samples (re-[add] the
  /// points from [pointCount] on). Returns the checkpoint's id, or null when
  /// there is none (start over).
  int? rollBack(int sample) {
    for (var k = _checkpoints.length - 1; k >= 0; k--) {
      final c = _checkpoints[k];
      // Final segments end before c.seg; they use samples up to c.seg + 1.
      if (c.seg + 2 > sample || c.resFinal == 0) continue;
      _checkpoints.removeRange(k + 1, _checkpoints.length);
      c.restore(this, sample);
      return c.id;
    }
    return null;
  }

  /// Computes the line for the input so far. With [ended] the input is
  /// complete: the start is decided with whatever there is, and the last
  /// [keep] input samples (the pen-up hook removed, see [endKeep]) are used.
  void update({bool ended = false, int? keep}) {
    if (_provisional) _restart();
    _ended = ended;
    final n = keep ?? _sx.length;
    _start ??= _hooks.startCut(_sx, _sy, n, ended: ended);
    if (n == 0) {
      length = finalCount = 0;
      corners = const [];
      return;
    }
    final start = _start ?? 0;
    _provisional = _start == null;
    _resample(start, n, ended: ended);
    final count = _rx.length;
    _radii(count);
    _findCorners(count);
    _smooth(count);
    _endRules(count);
    _taper(count, ended: ended);
    length = count;
    finalCount = _provisional ? 0 : math.min(_posFinal, _roDone);
  }

  /// Forgets the line computed while the start was undecided.
  void _restart() {
    _provisional = false;
    for (final b in [_rx, _ry, _rr, _r1, _r2, _rs, _cx, _cy, _ro, _rt]) {
      b.length = 0;
    }
    _resFinal = _seg = _radDone = _scan = _posFinal = _roDone = _rtFrom = 0;
    _next = 0;
    _corners.clear();
    _runFirst = _runBest = -1;
    _runScore = 0;
  }

  /// The number of input samples to keep once the stroke has ended.
  int endKeep() => _hooks.endKeep(_sx, _sy, _sx.length);

  /// The length of the resampling spline's segment from (x1, y1) to
  /// (x2, y2) with neighbours (x0, y0) and (x3, y3), flattened as the
  /// shaper flattens it for [step] (the overlay tracks where the whole
  /// line's samples fall).
  static double segmentLength(
    double x0,
    double y0,
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
    double step,
  ) {
    return _splineLength(x0, y0, x1, y1, x2, y2, x3, y3, step);
  }

  /// A copy of the line's samples (for measurements).
  ({Float64List x, Float64List y, Float64List r}) snapshot() =>
      (x: _cx.toList(), y: _cy.toList(), r: r.toList());
}

double _dist(double dx, double dy) => math.sqrt(dx * dx + dy * dy);
