import 'dart:math' as math;
import 'dart:ui';

import '../../domain/shape_geometry.dart';
import 'bezier.dart';

/// Curves through points: κ-curves (Z. Yan, S. Schiller, G. Wilensky,
/// N. Carr, S. Schaefer, "κ-Curves: Interpolation at Local Maximum
/// Curvature", ACM TOG 36(4), SIGGRAPH 2017; Adobe's Curvature tool).
///
/// The curve passes through every point, and bends most exactly there: one
/// quadratic Bézier per point, which it passes through where that piece's
/// curvature peaks; neighbouring pieces meet with matching tangents and
/// curvature (G²), except at inflections (G¹, the curvature's size still
/// matching). So no bump, loop or cusp appears between points, and a curve
/// edited point by point stays calm. The pieces are found by the paper's
/// local/global iteration: from the current pieces, where each meets the
/// next ([_lambdas]) and where it peaks ([_peak]); then the middle control
/// points from one (cyclic) tridiagonal linear system; a dozen rounds or so
/// converge.
///
/// An open curve's first and last points are its ends (of least curvature,
/// not peaks). A corner splits the curve into open pieces that meet there
/// at an angle. The quadratics are stored as the cubic Bézier spline every
/// curve keeps ([ShapeGeometry.points]: degree elevation is exact), with
/// the points themselves as [ShapeGeometry.through].
abstract final class KappaCurve {
  /// The curve through [through] ([closed] or open; [corners]: indices of
  /// sharp points, an open curve's ends never), as a shape: its cubic
  /// spline and its points. Closed curves need three points, open ones two.
  static ShapeGeometry geometry(
    List<Offset> through, {
    required bool closed,
    List<int> corners = const [],
    String? origin,
  }) {
    final n = through.length;
    final sharp = {
      for (final c in corners)
        if (c >= 0 && c < n && (closed || (c > 0 && c < n - 1))) c,
    }.toList()..sort();
    return ShapeGeometry(
      ShapeKind.curve,
      spline(through, closed: closed, corners: sharp),
      through: through,
      corners: sharp,
      origin: origin,
    );
  }

  /// [shape] (a curve through points) with its points [through] and
  /// [corners] instead, rebuilt.
  static ShapeGeometry reshaped(ShapeGeometry shape, List<Offset> through, {List<int>? corners}) =>
      geometry(
        through,
        closed: shape.isClosed,
        corners: corners ?? shape.corners,
        origin: shape.origin,
      );

  /// [shape] (a curve through points) with a point added where [at] (on
  /// or near its line) is, between the points either side of it.
  static ShapeGeometry withPointAt(ShapeGeometry shape, Offset at) {
    final through = shape.through!, closed = shape.isClosed;
    double along(Offset p) {
      final hit = Bezier.nearest(shape.points, p, closed: closed);
      return hit.segment + hit.t;
    }

    final hit = Bezier.nearest(shape.points, at, closed: closed);
    final where = hit.segment + hit.t;
    final on = Bezier.cubicAt(
      shape.points[3 * hit.segment],
      shape.points[3 * hit.segment + 1],
      shape.points[3 * hit.segment + 2],
      shape.points[(3 * hit.segment + 3) % shape.points.length],
      hit.t,
    );
    // After the last point before it along the curve.
    var index = closed ? through.length : 1;
    for (var i = 0; i < through.length; i++) {
      if (along(through[i]) < where) index = i + 1;
    }
    if (!closed) index = index.clamp(1, through.length - 1);
    return reshaped(
      shape,
      [...through.sublist(0, index), on, ...through.sublist(index)],
      corners: [for (final c in shape.corners) c >= index ? c + 1 : c],
    );
  }

  /// [shape] (a curve through points) without point [index]; the curve
  /// runs on through the others.
  static ShapeGeometry withoutPoint(ShapeGeometry shape, int index) => reshaped(
    shape,
    [...shape.through!]..removeAt(index),
    corners: [
      for (final c in shape.corners)
        if (c != index) c > index ? c - 1 : c,
    ],
  );

  /// The fewest points a curve through points keeps: two open, three
  /// closed.
  static int minPoints(ShapeGeometry shape) => shape.isClosed ? 3 : 2;

  /// The cubic Bézier spline (anchor, out, in, anchor, …; closed: `3n`
  /// points, the last the first anchor's in handle) of the curve through
  /// [through].
  static List<Offset> spline(
    List<Offset> through, {
    required bool closed,
    List<int> corners = const [],
  }) {
    final quads = quadratics(through, closed: closed, corners: corners);
    final out = <Offset>[];
    for (final [a, b, c] in quads) {
      out.addAll([a, a + (b - a) * (2 / 3), c + (b - c) * (2 / 3)]);
    }
    if (!closed) out.add(quads.last[2]);
    return out;
  }

  /// The quadratic pieces (`[start, control, end]`, each ending where the
  /// next starts) of the curve through [through], in order; a closed
  /// curve's last ends where its first starts.
  static List<List<Offset>> quadratics(
    List<Offset> through, {
    required bool closed,
    List<int> corners = const [],
  }) {
    final n = through.length;
    if (n < 2) {
      return [
        [through.first, through.first, through.first],
      ];
    }
    if (closed && n < 3) return quadratics([...through, through.first], closed: false);
    final sharp = {for (final c in corners) c % n};
    if (!closed) {
      final out = <List<Offset>>[];
      var from = 0;
      for (var i = 1; i < n; i++) {
        if (i == n - 1 || sharp.contains(i)) {
          out.addAll(_open(through.sublist(from, i + 1)));
          from = i;
        }
      }
      return out;
    }
    if (sharp.isEmpty) return _closed(through);
    // Closed with corners: open pieces from corner to corner, round.
    final first = sharp.reduce(math.min);
    final ring = [for (var i = 0; i <= n; i++) through[(first + i) % n]];
    final local = [for (final c in sharp) (c - first) % n];
    return quadratics(ring, closed: false, corners: local);
  }

  /// Rounds of the local/global iteration.
  static const int rounds = 24;

  /// An open curve from [p.first] to [p.last] through the others.
  static List<List<Offset>> _open(List<Offset> p) {
    if (p.length == 2) {
      return [
        [p[0], Offset.lerp(p[0], p[1], 0.5)!, p[1]],
      ];
    }
    final (q, unscale) = _normalised(p);
    final m = q.length - 2; // inner points, one piece each
    final inner = q.sublist(1, m + 1);
    var c1 = [...inner];
    var lambdas = List.filled(m - 1, 0.5);
    Offset start(int i) => i == 0 ? q.first : _join(c1[i - 1], c1[i], lambdas[i - 1]);
    Offset end(int i) => i == m - 1 ? q.last : _join(c1[i], c1[i + 1], lambdas[i]);
    for (var round = 0; round < rounds; round++) {
      // Local: where the pieces meet (G²), then where each peaks.
      if (round > 0) {
        lambdas = [for (var i = 0; i < m - 1; i++) _lambda(start(i), c1[i], c1[i + 1], end(i + 1))];
      }
      final t = [for (var i = 0; i < m; i++) _peak(start(i), inner[i], end(i))];
      // Global: p_i = (1 − t)² c_{i,0} + 2t(1 − t) c_{i,1} + t² c_{i,2}, with
      // the joins written in the middle points: tridiagonal in c_{·,1}.
      final lower = List.filled(m, 0.0), diag = List.filled(m, 0.0), upper = List.filled(m, 0.0);
      final rhs = List.filled(m, Offset.zero);
      for (var i = 0; i < m; i++) {
        final ti = t[i], s2 = (1 - ti) * (1 - ti), t2 = ti * ti;
        var d = 2 * ti * (1 - ti);
        var r = inner[i];
        if (i == 0) {
          r -= q.first * s2;
        } else {
          lower[i] = (1 - lambdas[i - 1]) * s2;
          d += lambdas[i - 1] * s2;
        }
        if (i == m - 1) {
          r -= q.last * t2;
        } else {
          upper[i] = lambdas[i] * t2;
          d += (1 - lambdas[i]) * t2;
        }
        diag[i] = d;
        rhs[i] = r;
      }
      c1 = _tridiagonal(lower, diag, upper, rhs);
    }
    return [
      for (var i = 0; i < m; i++)
        [
          for (final p in [start(i), c1[i], end(i)]) unscale(p),
        ],
    ];
  }

  /// A closed curve through every point of [p] (at least three).
  static List<List<Offset>> _closed(List<Offset> p) {
    final (q, unscale) = _normalised(p);
    final n = q.length;
    var c1 = [...q];
    var lambdas = List.filled(n, 0.5);
    // Piece i runs from join i − 1 to join i.
    Offset join(int i) => _join(c1[i % n], c1[(i + 1) % n], lambdas[i % n]);
    for (var round = 0; round < rounds; round++) {
      if (round > 0) {
        lambdas = [
          for (var i = 0; i < n; i++) _lambda(join(i + n - 1), c1[i], c1[(i + 1) % n], join(i + 1)),
        ];
      }
      final t = [for (var i = 0; i < n; i++) _peak(join(i + n - 1), q[i], join(i))];
      final lower = List.filled(n, 0.0), diag = List.filled(n, 0.0), upper = List.filled(n, 0.0);
      for (var i = 0; i < n; i++) {
        final ti = t[i], s2 = (1 - ti) * (1 - ti), t2 = ti * ti, before = lambdas[(i + n - 1) % n];
        lower[i] = (1 - before) * s2;
        upper[i] = lambdas[i] * t2;
        diag[i] = before * s2 + 2 * ti * (1 - ti) + (1 - lambdas[i]) * t2;
      }
      c1 = _cyclic(lower, diag, upper, q);
    }
    return [
      for (var i = 0; i < n; i++)
        [
          for (final p in [join(i + n - 1), c1[i], join(i)]) unscale(p),
        ],
    ];
  }

  /// Where the piece with middle point [a] meets the next (middle [b]).
  static Offset _join(Offset a, Offset b, double lambda) => a * (1 - lambda) + b * lambda;

  /// Where on the join between middle points [b] and [c] the curvature
  /// matches (G²): from the areas of the triangles either side (the
  /// paper's eq. 7; [a] starts the first piece, [d] ends the second).
  static double _lambda(Offset a, Offset b, Offset c, Offset d) {
    const epsilon = 1e-10;
    final x = math.sqrt(_area(a, b, c)) + epsilon, y = math.sqrt(_area(b, c, d)) + epsilon;
    return x / (x + y);
  }

  static double _area(Offset a, Offset b, Offset c) =>
      ((b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx)).abs() / 2;

  /// The parameter at which the quadratic from [c0] to [c2] through [p]
  /// peaks in curvature there: the one root in [0, 1] of the paper's
  /// cubic (eq. 4), found by bisection (it is negative at 0, positive at
  /// 1). Kept off the ends, where the middle point would run off.
  static double _peak(Offset c0, Offset p, Offset c2) {
    final a = (c2 - c0).distanceSquared;
    final b = 3 * _dot(c2 - c0, c0 - p);
    final c = _dot(c0 * 3 - p * 2 - c2, c0 - p);
    final d = -(c0 - p).distanceSquared;
    double f(double t) => ((a * t + b) * t + c) * t + d;
    var lo = 0.0, hi = 1.0;
    for (var i = 0; i < 48; i++) {
      final mid = (lo + hi) / 2;
      if (f(mid) < 0) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return ((lo + hi) / 2).clamp(0.01, 0.99);
  }

  static double _dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;

  /// [p] moved and scaled to about unit size (so the iteration's epsilon
  /// means the same at any size and place), and the way back.
  static (List<Offset>, Offset Function(Offset)) _normalised(List<Offset> p) {
    var sum = Offset.zero;
    for (final q in p) {
      sum += q;
    }
    final mean = sum / p.length.toDouble();
    var size = 0.0;
    for (final q in p) {
      size = math.max(size, (q - mean).distance);
    }
    if (size == 0) size = 1;
    return ([for (final q in p) (q - mean) / size], (q) => mean + q * size);
  }

  /// Solves the tridiagonal system `lower[i] x[i−1] + diag[i] x[i] +
  /// upper[i] x[i+1] = rhs[i]` (Thomas).
  static List<Offset> _tridiagonal(
    List<double> lower,
    List<double> diag,
    List<double> upper,
    List<Offset> rhs,
  ) {
    final n = diag.length;
    final c = List.filled(n, 0.0), d = List.filled(n, Offset.zero);
    for (var i = 0; i < n; i++) {
      final m = diag[i] - (i > 0 ? lower[i] * c[i - 1] : 0);
      c[i] = upper[i] / m;
      d[i] = (rhs[i] - (i > 0 ? d[i - 1] * lower[i] : Offset.zero)) / m;
    }
    for (var i = n - 2; i >= 0; i--) {
      d[i] -= d[i + 1] * c[i];
    }
    return d;
  }

  /// Solves the cyclic tridiagonal system (`lower[0]` couples the first
  /// unknown to the last, `upper[n−1]` the last to the first) by
  /// Sherman–Morrison on [_tridiagonal].
  static List<Offset> _cyclic(
    List<double> lower,
    List<double> diag,
    List<double> upper,
    List<Offset> rhs,
  ) {
    final n = diag.length;
    final alpha = upper[n - 1], beta = lower[0];
    final gamma = -diag[0];
    final b = [...diag];
    b[0] -= gamma;
    b[n - 1] -= alpha * beta / gamma;
    final lo = [0.0, ...lower.sublist(1)], up = [...upper.sublist(0, n - 1), 0.0];
    final x = _tridiagonal(lo, b, up, rhs);
    final u = List.filled(n, Offset.zero);
    u[0] = Offset(gamma, gamma);
    u[n - 1] = Offset(alpha, alpha);
    final z = _tridiagonal(lo, b, up, u);
    final vx = x[0].dx + beta / gamma * x[n - 1].dx, vy = x[0].dy + beta / gamma * x[n - 1].dy;
    final wx = 1 + z[0].dx + beta / gamma * z[n - 1].dx;
    final wy = 1 + z[0].dy + beta / gamma * z[n - 1].dy;
    return [
      for (var i = 0; i < n; i++) Offset(x[i].dx - vx / wx * z[i].dx, x[i].dy - vy / wy * z[i].dy),
    ];
  }
}
