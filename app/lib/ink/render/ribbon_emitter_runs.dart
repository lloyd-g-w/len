part of 'ribbon_emitter.dart';

/// Runs: one closed contour of fitted cubics with caps per run.
extension _Runs on RibbonEmitter {
  /// One closed contour around samples [a]..[b] (within stretch [lo]..[hi]):
  /// caps at both ends, or straight cuts where [startCut] / [endCut]; [first]
  /// replaces the offset points of [a] (a join, see [RibbonJoin]).
  void _run(
    OutlineSink sink,
    int a,
    int b,
    int lo,
    int hi, {
    bool startCut = false,
    bool endCut = false,
    _Offsets? first,
  }) {
    final o = [for (var i = a; i <= b; i++) i == a && first != null ? first : _offsets(i, lo, hi)];
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
      final stop = math.min(b, math.min(k0 + RibbonEmitter._maxSpan, (k0 ~/ block + 1) * block));
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
