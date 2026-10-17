import 'dart:math' as math;
import 'dart:ui';

import 'bezier.dart';

/// Fits a cubic Bézier spline to digitised points (Philip J. Schneider,
/// "An Algorithm for Automatically Fitting Digitized Curves", Graphics
/// Gems, 1990): one cubic by least squares on chord-length parameters,
/// refined by Newton–Raphson; where it misses by more than the error
/// allowed, split at the worst point (the tangent there shared, so the
/// spline stays smooth) and fit both halves.
abstract final class CurveFit {
  /// The spline (anchor, out, in, anchor, …) through [points] within
  /// [maxError] (largest distance), open; closed when [closed] (the
  /// points then loop back to their first: `3n` points, the last being
  /// the first anchor's in handle).
  static List<Offset> fit(List<Offset> points, double maxError, {bool closed = false}) {
    final d = closed ? [...points, points.first] : points;
    if (d.length < 2) return [d.first, d.first, d.first, d.first];
    final Offset start, end;
    if (closed) {
      final t = _unit(d[1] - d[d.length - 2]);
      start = t;
      end = -t;
    } else {
      start = _unit(d[1] - d[0]);
      end = _unit(d[d.length - 2] - d[d.length - 1]);
    }
    final out = <Offset>[d.first];
    _fitCubic(d, 0, d.length - 1, start, end, maxError, out);
    return closed ? out.sublist(0, out.length - 1) : out;
  }

  static void _fitCubic(
    List<Offset> d,
    int first,
    int last,
    Offset tHat1,
    Offset tHat2,
    double error,
    List<Offset> out,
  ) {
    if (last - first == 1) {
      final dist = (d[last] - d[first]).distance / 3;
      out.addAll([d[first] + tHat1 * dist, d[last] + tHat2 * dist, d[last]]);
      return;
    }
    var u = _chordLength(d, first, last);
    var bez = _generate(d, first, last, u, tHat1, tHat2);
    var (maxError, split) = _maxError(d, first, last, bez, u);
    if (maxError < error) {
      out.addAll(bez.sublist(1));
      return;
    }
    // Close enough to be worth reparameterising before splitting.
    if (maxError < error * 16) {
      for (var i = 0; i < 12; i++) {
        u = _reparameterise(d, first, last, u, bez);
        bez = _generate(d, first, last, u, tHat1, tHat2);
        (maxError, split) = _maxError(d, first, last, bez, u);
        if (maxError < error) {
          out.addAll(bez.sublist(1));
          return;
        }
      }
    }
    final centre = _unit(d[split - 1] - d[split + 1]);
    _fitCubic(d, first, split, tHat1, centre, error, out);
    _fitCubic(d, split, last, -centre, tHat2, error, out);
  }

  /// The cubic from d[first] to d[last] with end tangents [tHat1] and
  /// [tHat2] fitting the points at parameters [u] best (least squares on
  /// the two handle lengths).
  static List<Offset> _generate(
    List<Offset> d,
    int first,
    int last,
    List<double> u,
    Offset tHat1,
    Offset tHat2,
  ) {
    final p0 = d[first], p3 = d[last];
    var c00 = 0.0, c01 = 0.0, c11 = 0.0, x0 = 0.0, x1 = 0.0;
    for (var i = 0; i < u.length; i++) {
      final t = u[i], s = 1 - t;
      final b0 = s * s * s, b1 = 3 * t * s * s, b2 = 3 * t * t * s, b3 = t * t * t;
      final a1 = tHat1 * b1, a2 = tHat2 * b2;
      c00 += _dot(a1, a1);
      c01 += _dot(a1, a2);
      c11 += _dot(a2, a2);
      final tmp = d[first + i] - (p0 * (b0 + b1) + p3 * (b2 + b3));
      x0 += _dot(a1, tmp);
      x1 += _dot(a2, tmp);
    }
    final det = c00 * c11 - c01 * c01;
    var alpha1 = det == 0 ? 0.0 : (x0 * c11 - x1 * c01) / det;
    var alpha2 = det == 0 ? 0.0 : (c00 * x1 - c01 * x0) / det;
    final segLength = (p3 - p0).distance, epsilon = 1e-6 * segLength;
    // A degenerate or backwards fit: Wu/Barsky's heuristic, a third of
    // the chord along each tangent.
    if (alpha1 < epsilon || alpha2 < epsilon) alpha1 = alpha2 = segLength / 3;
    return [p0, p0 + tHat1 * alpha1, p3 + tHat2 * alpha2, p3];
  }

  static List<double> _chordLength(List<Offset> d, int first, int last) {
    final u = <double>[0];
    for (var i = first + 1; i <= last; i++) {
      u.add(u.last + (d[i] - d[i - 1]).distance);
    }
    final total = u.last;
    return [for (final v in u) total == 0 ? 0.0 : v / total];
  }

  /// The largest distance of the points from [bez] and where it is.
  static (double, int) _maxError(
    List<Offset> d,
    int first,
    int last,
    List<Offset> bez,
    List<double> u,
  ) {
    var maxDist = 0.0;
    var split = (last - first + 1) ~/ 2 + first;
    for (var i = first + 1; i < last; i++) {
      final p = Bezier.cubicAt(bez[0], bez[1], bez[2], bez[3], u[i - first]);
      final dist = (p - d[i]).distance;
      if (dist >= maxDist) {
        maxDist = dist;
        split = i;
      }
    }
    return (maxDist, split);
  }

  /// Better parameters: one Newton–Raphson step towards each point's
  /// nearest spot on [bez].
  static List<double> _reparameterise(
    List<Offset> d,
    int first,
    int last,
    List<double> u,
    List<Offset> bez,
  ) {
    final [a, b, c, e] = bez;
    // The first and second derivatives' control points.
    final q1 = [(b - a) * 3, (c - b) * 3, (e - c) * 3];
    final q2 = [(q1[1] - q1[0]) * 2, (q1[2] - q1[1]) * 2];
    return [
      for (var i = 0; i < u.length; i++)
        () {
          final t = u[i], s = 1 - t;
          final p = Bezier.cubicAt(a, b, c, e, t);
          final d1 = q1[0] * (s * s) + q1[1] * (2 * s * t) + q1[2] * (t * t);
          final d2 = q2[0] * s + q2[1] * t;
          final diff = p - d[first + i];
          final numerator = _dot(diff, d1);
          final denominator = _dot(d1, d1) + _dot(diff, d2);
          if (denominator == 0) return t;
          return (t - numerator / denominator).clamp(0.0, 1.0);
        }(),
    ];
  }

  static double _dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;

  static Offset _unit(Offset v) {
    final l = v.distance;
    return l == 0 ? const Offset(1, 0) : v / l;
  }

  /// The angle (radians) a polyline turns through in all, its turns
  /// counted whatever their side.
  static double totalTurning(List<Offset> p) {
    var total = 0.0;
    for (var i = 1; i < p.length - 1; i++) {
      total += _turn(p[i] - p[i - 1], p[i + 1] - p[i]).abs();
    }
    return total;
  }

  /// The signed angle from [a] to [b] (radians).
  static double _turn(Offset a, Offset b) =>
      math.atan2(a.dx * b.dy - a.dy * b.dx, a.dx * b.dx + a.dy * b.dy);

  /// The signed turn at each of [p]'s inner points, over [k] points each
  /// side (0 at the ends; wrapping round when [closed]).
  static List<double> turns(List<Offset> p, int k, {bool closed = false}) {
    final n = p.length;
    return [
      for (var i = 0; i < n; i++)
        if (!closed && (i < k || i >= n - k))
          0.0
        else
          _turn(p[i] - p[(i - k) % n], p[(i + k) % n] - p[i]),
    ];
  }
}
