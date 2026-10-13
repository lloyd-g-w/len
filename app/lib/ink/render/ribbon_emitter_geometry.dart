part of 'ribbon_emitter.dart';

/// Geometry per sample: tangents, offset points, folds and capsules.
extension _Geometry on RibbonEmitter {
  /// Unit tangent and radius slope at [i] within the stretch [lo]..[hi].
  (double, double, double) _frame(int i, int lo, int hi) {
    final x = line.x, y = line.y, r = line.r;
    var a = math.max(lo, i - 1), c = math.min(hi, i + 1);
    // A flat end is square to where the line runs over its last half
    // radius: the line's first and last samples are where the pen was
    // (`StrokeShaper` keeps the ends of stretches), and the step to them
    // may turn away from the smoothed line before it.
    if (flatCaps && hi - lo >= 3 && (i == 0 || (i == line.length - 1 && i == hi))) {
      final k = math.max(1, (0.5 * r[i] / _step).ceil());
      (a, c) = i == 0 ? (1, math.min(hi - 1, 1 + k)) : (math.max(lo + 1, i - 1 - k), i - 1);
    }
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
    final min = RibbonEmitter.foldAdvance * u * u; // along the chord, a side must advance enough
    if ((b.lx - a.lx) * ux + (b.ly - a.ly) * uy < min) return true;
    if ((b.rx - a.rx) * ux + (b.ry - a.ry) * uy < min) return true;
    return a.tx * b.tx + a.ty * b.ty < RibbonEmitter.foldCos;
  }

  void _capsule(OutlineSink sink, int i) {
    final x = line.x, y = line.y, r = line.r;
    emitCapsule(sink, x[i], y[i], r[i], x[i + 1], y[i + 1], r[i + 1]);
  }
}

class _Offsets {
  const _Offsets(this.lx, this.ly, this.rx, this.ry, this.tx, this.ty);
  final double lx, ly, rx, ry, tx, ty;
}
