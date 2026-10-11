import 'dart:math' as math;

import 'capsule_emitter.dart';
import 'growable.dart';
import 'outline_sink.dart';

/// The centre line a [RibbonEmitter] outlines: positions and radii of
/// uniformly spaced samples, and the corners that split it into stretches.
abstract interface class RibbonLine {
  DoubleBuffer get x;
  DoubleBuffer get y;
  DoubleBuffer get r;
  int get length;
  List<int> get corners;
}

/// Where the live outline's frozen part ends: the sample, and whether the
/// outline continues there with a straight cut (inside a run) rather than
/// a new run's cap.
typedef RibbonCursor = ({int at, bool cut});

/// Turns a centre line with radii into a filled outline made of few, smooth
/// contours.
///
/// The outline of a variable-width stroke is the envelope of its circles:
/// each side is offset from the centre line by the radius, along the
/// normal tilted by the radius slope (`c + r(−r′t ± √(1−r′²)n)`). A *run* of
/// samples becomes one closed contour — left side forward, a round cap,
/// right side back, a round cap — whose sides are cubic Béziers fitted to
/// the offset points (tangent at every join, a few verbs per pen-width of
/// length), so the edges are smooth at any zoom and the GPU fills one
/// simple contour instead of thousands of capsules.
///
/// Runs end where the envelope would fold: at corners (cusps, where the
/// line doubles back) and wherever a side would run backwards (a bend
/// tighter than the radius). Such segments are drawn as exact capsules
/// (the hull of their two circles). Neighbouring contours overlap in their
/// round caps, and all wind the same way, so the non-zero fill unions them.
///
/// Every decision is made from samples at most two ahead, and runs are cut
/// into pieces at fixed sample indices (multiples of [block]), so the live
/// stroke can [freeze] final pieces once and only rebuild its tail.
class RibbonEmitter {
  RibbonEmitter(this.line, {required this.flatCaps, required this.width, required double step})
    : tolerance = math.min(0.004, 0.002 * (1 + width)),
      block = math.max(16, (24 / step).ceil());

  final RibbonLine line;
  final bool flatCaps;
  final double width;

  /// Largest distance between a fitted side and its offset points (world
  /// units). The cubic that reaches into a live stroke's not-yet-final tip
  /// is refitted every frame and may move by up to twice this along its
  /// whole span (up to [_maxSpan] samples), so it is kept well below a
  /// physical pixel even when zoomed in 8×.
  final double tolerance;

  /// Runs are split into pieces at sample indices that are multiples of
  /// this (forced curve keys, where the live stroke may cut).
  final int block;

  static const int _maxSpan = 32;

  /// Within a run, a side may not run backwards by more than this many
  /// centre-line steps per step (a mild fold of the inner side, at a bend
  /// tighter than the radius, is fine: the non-zero fill still covers
  /// exactly the union of the circles, see test/ribbon_exactness_test.dart).
  static double foldAdvance = -2;

  /// Cosine of the largest tangent turn per sample within a run.
  static double foldCos = -0.5;

  /// Emits the whole outline from [from] to the end of the line. With
  /// [cut], the outline starts at [from] with a straight cut (the frozen
  /// part of a live stroke ends there).
  void emit(OutlineSink sink, {RibbonCursor from = (at: 0, cut: false)}) => _walk(sink, from, null);

  /// Emits the pieces from [from] whose geometry only depends on the first
  /// [finalCount] samples, each as its own contour; returns where the
  /// frozen part now ends.
  RibbonCursor freeze(OutlineSink sink, RibbonCursor from, int finalCount) =>
      _walk(sink, from, finalCount);

  RibbonCursor _walk(OutlineSink sink, RibbonCursor from, int? limit) {
    final n = line.length;
    final bounds = [0, ...line.corners, n - 1];
    var b = 1;
    var i = from.at;
    var cut = from.cut;
    while (i < n - 1) {
      while (bounds[b] <= i) {
        b++;
      }
      final lo = bounds[b - 1], hi = bounds[b];
      if (limit != null && i + 3 >= limit) break;
      if (_folded(i, lo, hi)) {
        _capsule(sink, i);
        i++;
        cut = false;
        continue;
      }
      // A run from i to its end j.
      var j = i + 1;
      var open = false; // not known yet where the run ends
      while (j < hi) {
        if (limit != null && j + 3 >= limit) {
          open = true;
          break;
        }
        if (_folded(j, lo, hi)) break;
        j++;
      }
      if (limit == null) {
        _run(sink, i, j, lo, hi, startCut: cut);
        i = j;
        cut = false;
        continue;
      }
      // Freezing: each final piece as its own contour.
      var p = i;
      while (p < j) {
        final q = math.min(j, (p ~/ block + 1) * block);
        if (q == j && open) break;
        _run(sink, p, q, lo, hi, startCut: p == i ? cut : true, endCut: q < j);
        p = q;
      }
      if (p < j || open) return (at: p, cut: p > i || cut);
      i = j;
      cut = false;
    }
    return (at: i, cut: cut);
  }

  // ---------------------------------------------------------------------------
  // Geometry per sample

  /// Unit tangent and radius slope at [i] within the stretch [lo]..[hi].
  (double, double, double) _frame(int i, int lo, int hi) {
    final x = line.x, y = line.y, r = line.r;
    var a = math.max(lo, i - 1), c = math.min(hi, i + 1);
    var dx = x[c] - x[a], dy = y[c] - y[a];
    var d = math.sqrt(dx * dx + dy * dy);
    // Coincident neighbours (a pinned tip): look one further.
    if (d < 1e-9 && (a > lo || c < hi)) {
      a = math.max(lo, a - 1);
      c = math.min(hi, c + 1);
      dx = x[c] - x[a];
      dy = y[c] - y[a];
      d = math.sqrt(dx * dx + dy * dy);
    }
    if (d < 1e-9) return (1, 0, 0);
    final slope = ((r[c] - r[a]) / d).clamp(-0.9, 0.9);
    return (dx / d, dy / d, slope);
  }

  /// Left and right offset points of [i] and its tangent.
  _Offsets _offsets(int i, int lo, int hi) {
    final (tx, ty, s) = _frame(i, lo, hi);
    final cx = line.x[i], cy = line.y[i], r = line.r[i];
    final along = -r * s, across = r * math.sqrt(1 - s * s);
    final nx = -ty, ny = tx;
    return _Offsets(
      cx + along * tx + across * nx,
      cy + along * ty + across * ny,
      cx + along * tx - across * nx,
      cy + along * ty - across * ny,
      tx,
      ty,
    );
  }

  /// Whether the envelope breaks over segment [i] → i + 1: the samples
  /// coincide, a side runs far backwards or the line turns too sharply
  /// for the sides to follow (cusps are corners and split runs anyway).
  bool _folded(int i, int lo, int hi) {
    final x = line.x, y = line.y;
    final ux = x[i + 1] - x[i], uy = y[i + 1] - y[i];
    final u = math.sqrt(ux * ux + uy * uy);
    if (u < 1e-9) return true;
    final a = _offsets(i, lo, hi), b = _offsets(i + 1, lo, hi);
    final min = foldAdvance * u * u; // along the chord, a side must advance enough
    if ((b.lx - a.lx) * ux + (b.ly - a.ly) * uy < min) return true;
    if ((b.rx - a.rx) * ux + (b.ry - a.ry) * uy < min) return true;
    return a.tx * b.tx + a.ty * b.ty < foldCos;
  }

  void _capsule(OutlineSink sink, int i) {
    final x = line.x, y = line.y, r = line.r;
    emitCapsule(sink, x[i], y[i], r[i], x[i + 1], y[i + 1], r[i + 1]);
  }

  // ---------------------------------------------------------------------------
  // Runs

  /// One closed contour around samples [a]..[b] (within stretch [lo]..[hi]):
  /// caps at both ends, or straight cuts where [startCut] / [endCut].
  void _run(
    OutlineSink sink,
    int a,
    int b,
    int lo,
    int hi, {
    bool startCut = false,
    bool endCut = false,
  }) {
    final o = [for (var i = a; i <= b; i++) _offsets(i, lo, hi)];
    final left = _Side(this, o, a, left: true);
    final right = _Side(this, o, a, left: false);
    final keysL = _keys(left, a, b), keysR = _keys(right, a, b);
    final s = o.first, e = o.last;
    sink.moveTo(s.lx, s.ly);
    left.forward(sink, keysL);
    final n = line.length;
    if (endCut) {
      sink.lineTo(e.rx, e.ry);
    } else if (flatCaps && b == n - 1) {
      sink.lineTo(e.rx, e.ry);
    } else {
      _cap(sink, b, e.lx, e.ly, e.rx, e.ry, e.tx, e.ty);
    }
    right.backward(sink, keysR);
    if (!startCut && !(flatCaps && a == 0)) {
      _cap(sink, a, s.rx, s.ry, s.lx, s.ly, -s.tx, -s.ty);
    }
    sink.close();
  }

  /// Curve keys of [side] from [a] to [b]: forced at multiples of [block],
  /// otherwise as far apart as the [tolerance] allows (greedy from [a]).
  List<int> _keys(_Side side, int a, int b) {
    final keys = <int>[a];
    var k0 = a;
    while (k0 < b) {
      final stop = math.min(b, math.min(k0 + _maxSpan, (k0 ~/ block + 1) * block));
      var k1 = k0 + 1;
      while (k1 < stop && side.fits(k0, k1 + 1)) {
        k1++;
      }
      keys.add(k1);
      k0 = k1;
    }
    return keys;
  }

  /// The round cap around sample [i] from (ax, ay) to (bx, by), through
  /// direction (dx, dy).
  void _cap(
    OutlineSink sink,
    int i,
    double ax,
    double ay,
    double bx,
    double by,
    double dx,
    double dy,
  ) {
    final cx = line.x[i], cy = line.y[i], r = line.r[i];
    if (r <= 1e-9) {
      sink.lineTo(bx, by);
      return;
    }
    final from = math.atan2(ay - cy, ax - cx);
    final to = math.atan2(by - cy, bx - cx);
    // Sweep clockwise-negative from `from` to `to`, the long way round
    // through the cap's direction (a cap is at least a half circle minus
    // the radius slope's tilt).
    var sweep = to - from;
    while (sweep >= 0) {
      sweep -= 2 * math.pi;
    }
    while (sweep < -2 * math.pi) {
      sweep += 2 * math.pi;
    }
    sink.arc(cx, cy, r, from, sweep);
  }
}

class _Offsets {
  const _Offsets(this.lx, this.ly, this.rx, this.ry, this.tx, this.ty);
  final double lx, ly, rx, ry, tx, ty;
}

/// One side of a run: its offset points and how to fit cubics to them.
class _Side {
  _Side(this.e, this.o, this.a, {required this.left});

  final RibbonEmitter e;
  final List<_Offsets> o;
  final int a;
  final bool left;

  double px(int i) => left ? o[i - a].lx : o[i - a].rx;
  double py(int i) => left ? o[i - a].ly : o[i - a].ry;

  /// Unit direction of the side at [i]: perpendicular to the radius (the
  /// envelope touches the circle there), oriented along the line.
  (double, double) dir(int i) {
    final s = o[i - a];
    final cx = e.line.x[i], cy = e.line.y[i];
    var dx = -(py(i) - cy), dy = px(i) - cx;
    final d = math.sqrt(dx * dx + dy * dy);
    if (d < 1e-9) return (s.tx, s.ty);
    dx /= d;
    dy /= d;
    if (dx * s.tx + dy * s.ty < 0) return (-dx, -dy);
    return (dx, dy);
  }

  /// Length of the offset polyline from [k0] to [k1].
  double _length(int k0, int k1) {
    var total = 0.0;
    for (var i = k0 + 1; i <= k1; i++) {
      final dx = px(i) - px(i - 1), dy = py(i) - py(i - 1);
      total += math.sqrt(dx * dx + dy * dy);
    }
    return total;
  }

  /// Control points of the cubic from [k0] to [k1].
  (double, double, double, double) controls(int k0, int k1) {
    final h = _length(k0, k1) / 3;
    final (d0x, d0y) = dir(k0);
    final (d1x, d1y) = dir(k1);
    return (px(k0) + d0x * h, py(k0) + d0y * h, px(k1) - d1x * h, py(k1) - d1y * h);
  }

  /// Whether one cubic from [k0] to [k1] stays within tolerance of every
  /// offset point between them.
  bool fits(int k0, int k1) {
    final total = _length(k0, k1);
    if (total <= 0) return true;
    final (c1x, c1y, c2x, c2y) = controls(k0, k1);
    final x0 = px(k0), y0 = py(k0), x3 = px(k1), y3 = py(k1);
    var along = 0.0;
    final tol2 = e.tolerance * e.tolerance;
    for (var i = k0 + 1; i < k1; i++) {
      final dx = px(i) - px(i - 1), dy = py(i) - py(i - 1);
      along += math.sqrt(dx * dx + dy * dy);
      final t = along / total, u = 1 - t;
      final bx = u * u * u * x0 + 3 * u * u * t * c1x + 3 * u * t * t * c2x + t * t * t * x3;
      final by = u * u * u * y0 + 3 * u * u * t * c1y + 3 * u * t * t * c2y + t * t * t * y3;
      final ex = bx - px(i), ey = by - py(i);
      if (ex * ex + ey * ey > tol2) return false;
    }
    return true;
  }

  void forward(OutlineSink sink, List<int> keys) {
    for (var k = 1; k < keys.length; k++) {
      final (c1x, c1y, c2x, c2y) = controls(keys[k - 1], keys[k]);
      sink.cubicTo(c1x, c1y, c2x, c2y, px(keys[k]), py(keys[k]));
    }
  }

  void backward(OutlineSink sink, List<int> keys) {
    for (var k = keys.length - 1; k >= 1; k--) {
      final (c1x, c1y, c2x, c2y) = controls(keys[k - 1], keys[k]);
      sink.cubicTo(c2x, c2y, c1x, c1y, px(keys[k - 1]), py(keys[k - 1]));
    }
  }
}
