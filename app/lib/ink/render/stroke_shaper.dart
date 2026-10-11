import 'dart:math' as math;
import 'dart:typed_data';

import 'growable.dart';
import 'hooks.dart';
import 'line_filters.dart';
import 'ribbon_emitter.dart';
import 'shape_params.dart';

/// Turns the input points of a stroke into its smoothed centre line with
/// radii, *incrementally* and with a fixed reach: every value further than
/// a fixed distance behind the pen tip is **final** — computed once, from
/// input that can no longer change, and bit-identical in every later frame
/// and in the committed stroke.
///
/// Stages (each one only looks a fixed number of samples ahead):
///  1. dedupe: points closer than a hair are merged (positions never move
///     afterwards; only the last radius may still grow);
///  2. pen-down hook: decided once from the first [ShapeParams.gate] of
///     length ([HookFinder]);
///  3. resampling every [ShapeParams.step] along a centripetal Catmull-Rom
///     spline through the samples, from the stroke's start (a segment is
///     final once the sample after its end is);
///  4. corners: where the line doubles back within a short baseline; the
///     sharpest sample of each such spot (final once the spot has passed);
///  5. positions: the finite low-pass kernel of [LineFilters.lowPassKernel]
///     per stretch between corners, each stretch continued beyond its ends
///     by a local quadratic fit (no lag, tips stay put);
///  6. radii: causal (two cascaded exponential passes, then a slope limit),
///     so final as soon as their sample is; then the end rules, which only
///     touch the first and last few samples.
///
/// [line] writes the whole line (final values plus the not-yet-final tail)
/// into the output buffers; only the tail is recomputed per call.
class StrokeShaper implements RibbonLine {
  /// A shaper for [p]. For a piece of a longer line (the low-latency
  /// overlay smooths only the newest part), [start] makes input sample
  /// `start − 1` a lead-in (only the spline's neighbour of the first
  /// segment) and [phase] is the arc length of the first resampled point
  /// after the start, so the samples fall where the whole line's do.
  StrokeShaper(this.p, {int? start, double? phase})
    : _hooks = p.hooks,
      _start = start,
      _leadIn = start != null && start > 0,
      _phase = phase;

  final ShapeParams p;
  final HookFinder _hooks;

  // 1. Deduplicated input samples (position, radius).
  final DoubleBuffer _sx = DoubleBuffer(), _sy = DoubleBuffer(), _sr = DoubleBuffer();

  // 2. First sample kept (pen-down hook), once decided.
  int? _start;
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
  int _runBest = -1;
  double _runTurn = 0;

  // 5. Smoothed positions; [_posFinal] of them final.
  final DoubleBuffer _cx = DoubleBuffer(), _cy = DoubleBuffer();
  int _posFinal = 0;

  // 6b. Output radii (end rules applied); [_roDone] of them final.
  final DoubleBuffer _ro = DoubleBuffer();
  int _roDone = 0;

  /// Corner sample indices of the last [update] (final and provisional).
  @override
  List<int> corners = const [];

  /// Number of samples of the last [update].
  @override
  int length = 0;

  /// Samples of the last [update] that are final (position and radius).
  int finalCount = 0;

  /// Whether the pen-down decision has been made (otherwise there is no
  /// line yet).
  bool get started => _start != null;

  /// The first input sample kept (after the pen-down hook); 0 until
  /// [started].
  int get startSample => _start ?? 0;

  @override
  DoubleBuffer get x => _cx;
  @override
  DoubleBuffer get y => _cy;
  @override
  DoubleBuffer get r => _ro;

  int get inputCount => _sx.length;

  /// The resampled, unsmoothed positions (for measurements).
  DoubleBuffer get rawX => _rx;
  DoubleBuffer get rawY => _ry;
  double inputX(int i) => _sx[i];
  double inputY(int i) => _sy[i];

  /// The largest input radius (a dot's size).
  double get maxInputRadius {
    var m = 0.0;
    for (var i = 0; i < _sr.length; i++) {
      m = math.max(m, _sr[i]);
    }
    return m;
  }

  /// Whether the start (pen-down hook, start rules) is decided and final.
  bool get startFinal => _start != null && _roDone > 0;

  /// Number of input points [add]ed so far.
  int pointCount = 0;

  // The first input point of each sample (merged points follow it).
  final List<int> _samplePoint = [];

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

  /// The input sample point [point] went into.
  int sampleOfPoint(int point) {
    var lo = 0, hi = _samplePoint.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (_samplePoint[mid] <= point) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  // ---------------------------------------------------------------------------
  // Checkpoints: the final state after recent [update]s, so the end of a
  // finished stroke (pen-up hook, settled pressures) can be redone without
  // starting over.

  final List<_Checkpoint> _checkpoints = [];
  static const int _keptCheckpoints = 48;

  /// Records the current final state; returns its id for [rollBack].
  int checkpoint() {
    _checkpoints.add(
      _Checkpoint(
        id: _checkpointIds++,
        seg: _seg,
        next: _next,
        resFinal: _resFinal,
        radDone: _radDone,
        corners: _corners.length,
        scan: _scan,
        runBest: _runBest,
        runTurn: _runTurn,
        posFinal: _posFinal,
        roDone: _roDone,
      ),
    );
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
      _seg = c.seg;
      _next = c.next;
      _resFinal = c.resFinal;
      _radDone = c.radDone;
      _corners.removeRange(c.corners, _corners.length);
      _scan = c.scan;
      _runBest = c.runBest;
      _runTurn = c.runTurn;
      _posFinal = c.posFinal;
      _roDone = c.roDone;
      _sx.length = sample;
      _sy.length = sample;
      _sr.length = sample;
      pointCount = _samplePoint[sample];
      _samplePoint.removeRange(sample, _samplePoint.length);
      return c.id;
    }
    return null;
  }

  /// Computes the line for the input so far. With [ended] the input is
  /// complete: the start is decided with whatever there is, and the last
  /// [keep] input samples (the pen-up hook removed, see [endKeep]) are used.
  void update({bool ended = false, int? keep}) {
    final n = keep ?? _sx.length;
    _start ??= _hooks.startCut(_sx, _sy, n, ended: ended);
    final start = _start;
    if (start == null || n == 0) {
      length = finalCount = 0;
      corners = const [];
      return;
    }
    _resample(start, n, ended: ended);
    final count = _rx.length;
    _radii(count);
    _findCorners(count);
    _smooth(count);
    _endRules(count, ended: ended);
    length = count;
    finalCount = math.min(_posFinal, _roDone);
  }

  /// The number of input samples to keep once the stroke has ended.
  int endKeep() => _hooks.endKeep(_sx, _sy, _sx.length);

  // ---------------------------------------------------------------------------
  // 3. Resampling

  void _resample(int start, int n, {required bool ended}) {
    // Final segments: the sample after the segment's end is final (only
    // the last input sample is not: its radius may still grow), and the
    // input must still be growing (an ended stroke's last segments use
    // the end reflection).
    _rx.length = _resFinal;
    _ry.length = _resFinal;
    _rr.length = _resFinal;
    if (_resFinal == 0) {
      _push(_sx[start], _sy[start], _sr[start]);
      _resFinal = 1;
      _seg = start;
      final phase = _phase;
      _next = phase != null && phase > 1e-9 ? phase : p.step;
    }
    while (_seg + 2 <= n - 2 && !ended) {
      _next = _segment(_seg, start, n, _next);
      _seg++;
      _resFinal = _rx.length;
    }
    var next = _next;
    for (var k = _seg; k < n - 1; k++) {
      next = _segment(k, start, n, next);
    }
    // The end sample itself (closer than a step to the one before).
    final along = next - p.step; // distance of the last sample before the end
    if (n - 1 > start && along < -p.step * 1e-3) _push(_sx[n - 1], _sy[n - 1], _sr[n - 1]);
  }

  /// Adds the samples of segment [k] (input samples k → k+1) at arc
  /// lengths [next], next + step, …; returns the arc length of the next
  /// sample measured from the start of segment k + 1.
  double _segment(int k, int start, int n, double next) {
    final x1 = _sx[k], y1 = _sy[k], x2 = _sx[k + 1], y2 = _sy[k + 1];
    final lead = k > start || (_leadIn && k > 0);
    final x0 = lead ? _sx[k - 1] : 2 * x1 - x2;
    final y0 = lead ? _sy[k - 1] : 2 * y1 - y2;
    final x3 = k + 2 < n ? _sx[k + 2] : 2 * x2 - x1;
    final y3 = k + 2 < n ? _sy[k + 2] : 2 * y2 - y1;
    final r1 = _sr[k], r2 = _sr[k + 1];
    final gap = _dist(x2 - x1, y2 - y1);
    final pieces = math.max(1, math.min(64, (gap / (p.step * 0.5)).ceil()));
    final cr = _CatmullRom(x0, y0, x1, y1, x2, y2, x3, y3);
    var ax = x1, ay = y1, along = 0.0;
    for (var q = 1; q <= pieces; q++) {
      final t = q / pieces;
      final (bx, by) = q == pieces ? (x2, y2) : cr.at(t);
      final len = _dist(bx - ax, by - ay);
      while (next <= along + len && len > 0) {
        final u = (next - along) / len;
        final tt = (q - 1 + u) / pieces;
        _push(ax + (bx - ax) * u, ay + (by - ay) * u, r1 + (r2 - r1) * tt);
        next += p.step;
      }
      along += len;
      ax = bx;
      ay = by;
    }
    return next - along;
  }

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
    final gap = _dist(x2 - x1, y2 - y1);
    final pieces = math.max(1, math.min(64, (gap / (step * 0.5)).ceil()));
    final cr = _CatmullRom(x0, y0, x1, y1, x2, y2, x3, y3);
    var ax = x1, ay = y1, along = 0.0;
    for (var q = 1; q <= pieces; q++) {
      final (bx, by) = q == pieces ? (x2, y2) : cr.at(q / pieces);
      along += _dist(bx - ax, by - ay);
      ax = bx;
      ay = by;
    }
    return along;
  }

  void _push(double x, double y, double r) {
    _rx.add(x);
    _ry.add(y);
    _rr.add(r);
  }

  // ---------------------------------------------------------------------------
  // 6a. Causal radii

  void _radii(int count) {
    final keep = p.radiusKeep, d = p.slope;
    // Values computed from final input in an earlier call are final.
    final from = _radDone;
    _r1.length = count;
    _r2.length = count;
    _rs.length = count;
    for (var i = from; i < count; i++) {
      if (i == 0) {
        _r1[0] = _r2[0] = _rs[0] = _rr[0];
        continue;
      }
      _r1[i] = _r1[i - 1] * keep + _rr[i] * (1 - keep);
      _r2[i] = _r2[i - 1] * keep + _r1[i] * (1 - keep);
      _rs[i] = _r2[i].clamp(_rs[i - 1] - d, _rs[i - 1] + d);
    }
    _radDone = _resFinal;
  }

  // ---------------------------------------------------------------------------
  // 4. Corners

  /// Turn (radians) at sample [i] over the corner baseline.
  double _turnAt(int i) {
    final k = p.cornerK;
    final ax = _rx[i] - _rx[i - k], ay = _ry[i] - _ry[i - k];
    final bx = _rx[i + k] - _rx[i], by = _ry[i + k] - _ry[i];
    return math.atan2(ax * by - ay * bx, ax * bx + ay * by).abs();
  }

  void _findCorners(int count) {
    final k = p.cornerK;
    if (_scan < k) _scan = k;
    // Final part: samples whose baseline reaches only final samples.
    while (_scan + k < _resFinal) {
      final turn = _turnAt(_scan);
      if (turn > ShapeParams.minTurn) {
        if (turn > _runTurn) {
          _runBest = _scan;
          _runTurn = turn;
        }
      } else if (_runBest >= 0) {
        _corners.add(_runBest);
        _runBest = -1;
        _runTurn = 0;
      }
      _scan++;
    }
    // Provisional part, from a copy of the scan state.
    final found = List<int>.of(_corners);
    var best = _runBest;
    var bestTurn = _runTurn;
    for (var i = _scan; i + k < count; i++) {
      final turn = _turnAt(i);
      if (turn > ShapeParams.minTurn) {
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

  // ---------------------------------------------------------------------------
  // 5. Positions

  void _smooth(int count) {
    _cx.length = count;
    _cy.length = count;
    final bounds = [0, ...corners, count - 1];
    var b = 1;
    for (var i = _posFinal; i < count; i++) {
      while (bounds[b] < i) {
        b++;
      }
      // Stretch [lo, hi] containing i (a corner belongs to the one before).
      final lo = bounds[b - 1], hi = bounds[b];
      _cx[i] = _filtered(_rx, i, lo, hi);
      _cy[i] = _filtered(_ry, i, lo, hi);
    }
    // Final: the window reaches neither a non-final sample nor where a
    // corner may still be found.
    final known = _runBest >= 0 ? _runBest : _scan;
    final settled = math.min(known, _resFinal) - p.kernelK - 1;
    if (settled > _posFinal) _posFinal = settled;
  }

  /// The low-pass value at [i] of [v] within the stretch [lo]..[hi].
  double _filtered(DoubleBuffer v, int i, int lo, int hi) {
    if (i == lo || i == hi || hi - lo < 2) return v[i];
    final w = p.kernel, k = p.kernelK;
    var sum = 0.0;
    final inLo = math.max(lo, i - k), inHi = math.min(hi, i + k);
    for (var m = inLo; m <= inHi; m++) {
      sum += w[m - i + k] * v[m];
    }
    if (i - k < lo) {
      final (a, c) = LineFilters.endFit(v, lo, 1, math.min(p.fit, hi - lo));
      for (var m = i - k; m < lo; m++) {
        final j = (lo - m).toDouble();
        sum += w[m - i + k] * (v[lo] + a * j + c * j * j);
      }
    }
    if (i + k > hi) {
      final (a, c) = LineFilters.endFit(v, hi, -1, math.min(p.fit, hi - lo));
      for (var m = hi + 1; m <= i + k; m++) {
        final j = (m - hi).toDouble();
        sum += w[m - i + k] * (v[hi] + a * j + c * j * j);
      }
    }
    return sum;
  }

  // ---------------------------------------------------------------------------
  // 6b. End rules

  void _endRules(int count, {required bool ended}) {
    _ro.length = count;
    final from = _roDone;
    for (var i = from; i < count; i++) {
      _ro[i] = _rs[i];
    }
    if (from == 0) {
      // Start: non-swelling, then levelled (final once the start reach is,
      // which the gate ensures before anything is shown).
      final ks = math.min(count - 1, p.settleK);
      for (var i = ks - 1; i >= 0; i--) {
        _ro[i] = math.min(_ro[i], _ro[i + 1]);
      }
      if (p.levelK > 0 && count > p.levelK) {
        final level = _ro[p.levelK];
        for (var i = 0; i < p.levelK; i++) {
          _ro[i] = math.max(_ro[i], level);
        }
      }
    }
    // End (the moving tip while drawing, the real end once ended).
    final ke = math.min(count - 1, p.settleEndK);
    for (var i = count - ke; i < count; i++) {
      if (i > 0) _ro[i] = math.min(_ro[i], _ro[i - 1]);
    }
    if (p.levelEndK > 0 && count > 2 * p.levelEndK) {
      final level = _ro[count - 1 - p.levelEndK];
      for (var i = count - p.levelEndK; i < count; i++) {
        _ro[i] = math.max(_ro[i], level);
      }
    }
    _taper(count, from, ended: ended);
    final settled = _resFinal - p.endReach;
    if (settled > p.startReach && settled > _roDone) _roDone = settled;
  }

  void _taper(int count, int from, {required bool ended}) {
    final total = p.step * (count - 1);
    var start = from == 0 ? p.taperStart : 0.0;
    var end = ended ? p.taperEnd : 0.0;
    if (ended) {
      start = math.min(start, total / 2);
      end = math.min(end, total / 2);
    }
    if (start <= 0 && end <= 0) return;
    double ease(double t) => t * (2 - t);
    for (var i = 0; i < count; i++) {
      final s = i * p.step;
      if (start > 0 && s < start) _ro[i] = math.max(0.02, _ro[i] * ease(s / start));
      if (end > 0 && total - s < end) _ro[i] = math.max(0.02, _ro[i] * ease((total - s) / end));
    }
  }

  /// A copy of the line's samples (for measurements).
  ({Float64List x, Float64List y, Float64List r}) snapshot() =>
      (x: _cx.toList(), y: _cy.toList(), r: _ro.toList());

  static double _dist(double dx, double dy) => math.sqrt(dx * dx + dy * dy);
}

class _Checkpoint {
  _Checkpoint({
    required this.id,
    required this.seg,
    required this.next,
    required this.resFinal,
    required this.radDone,
    required this.corners,
    required this.scan,
    required this.runBest,
    required this.runTurn,
    required this.posFinal,
    required this.roDone,
  });

  final int id;
  final int seg;
  final double next;
  final int resFinal, radDone, corners, scan, runBest;
  final double runTurn;
  final int posFinal, roDone;
}

/// One centripetal Catmull-Rom segment from P1 to P2 (Barry–Goldman form).
class _CatmullRom {
  _CatmullRom(this.x0, this.y0, this.x1, this.y1, this.x2, this.y2, this.x3, this.y3) {
    t1 = _knot(0, x0, y0, x1, y1);
    t2 = _knot(t1, x1, y1, x2, y2);
    t3 = _knot(t2, x2, y2, x3, y3);
  }

  final double x0, y0, x1, y1, x2, y2, x3, y3;
  late final double t1, t2, t3;

  static double _knot(double t, double ax, double ay, double bx, double by) {
    final d = math.sqrt(math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay)));
    return t + math.max(d, 1e-6);
  }

  (double, double) at(double u) {
    final t = t1 + (t2 - t1) * u;
    double lerp(double a, double b, double ta, double tb) =>
        (tb - t) / (tb - ta) * a + (t - ta) / (tb - ta) * b;
    final a1x = lerp(x0, x1, 0, t1), a1y = lerp(y0, y1, 0, t1);
    final a2x = lerp(x1, x2, t1, t2), a2y = lerp(y1, y2, t1, t2);
    final a3x = lerp(x2, x3, t2, t3), a3y = lerp(y2, y3, t2, t3);
    final b1x = lerp(a1x, a2x, 0, t2), b1y = lerp(a1y, a2y, 0, t2);
    final b2x = lerp(a2x, a3x, t1, t3), b2y = lerp(a2y, a3y, t1, t3);
    return (lerp(b1x, b2x, t1, t2), lerp(b1y, b2y, t1, t2));
  }
}
