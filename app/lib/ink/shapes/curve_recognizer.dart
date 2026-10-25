import 'dart:math' as math;
import 'dart:ui';

import '../../domain/shape_geometry.dart';
import 'kappa_curve.dart';
import 'polyline.dart';
import 'shape_builder.dart';
import 'shape_recognizer.dart';

/// Recognises a held stroke that is no other shape as a smooth curve: a
/// curve through a few of its points ([KappaCurve]), where it bends most.
/// Only smooth strokes qualify, and handwriting is not smooth: no corner
/// (no turn sharper than [maxTurn] over a few points: letters' cusps and
/// zig-zags), no loop (no crossing: "e", "l"), at most [maxTurning] of
/// turning in all and [maxInflections] changes of direction (no waves,
/// no spirals), and a curve within [maxError] of the stroke through a
/// handful of points ([maxOpenPoints], [maxClosedPoints]). Hold to snap
/// also requires a size ([HoldToStraighten.minCurve]).
///
/// The points ([_fit]): the stroke's ends and where it bends most (peaks
/// of its turning, as a κ-curve bends most at its points); then, while the
/// curve misses the stroke by more than [maxError], the point it misses
/// most is added; and last any point the curve can do without is dropped.
abstract final class CurveRecognizer {
  /// Points the stroke is resampled to.
  static const int samples = 64;

  /// The sharpest turn allowed over 3 samples each side (radians, 60°).
  static const double maxTurn = 60 * math.pi / 180;

  /// The most turning in all (radians), open and closed.
  static const double maxTurning = 2 * math.pi, maxClosedTurning = 4 * math.pi;

  /// The most changes between turning left and right, open and closed.
  static const int maxInflections = 2, maxClosedInflections = 4;

  /// The curve's largest distance from the stroke, relative to its
  /// bounding-box diagonal.
  static const double maxError = 0.015;

  /// The most points an open and a closed curve pass through.
  static const int maxOpenPoints = 5, maxClosedPoints = 6;

  /// A point is dropped only if the curve without it stays within this
  /// share of [maxError] (a point that brings it much closer stays).
  static const double dropTolerance = 0.6;

  /// A bend counts as one where a point goes when the stroke turns at
  /// least this much there (radians over 3 samples each side, 10°).
  static const double minBend = 10 * math.pi / 180;

  static ShapeGeometry? recognize(List<Offset> input) {
    final points = Polyline.dedupe(input);
    if (points.length < 8) return null;
    final bounds = Polyline.bounds(points);
    final diagonal = math.sqrt(bounds.width * bounds.width + bounds.height * bounds.height);
    if (diagonal == 0) return null;
    final length = Polyline.length(points);
    final gap = (points.last - points.first).distance;
    final closed = gap <= ShapeRecognizer.maxGap * diagonal && length >= 1.6 * diagonal;
    var s = Polyline.resample(closed ? Polyline.trimOverlap(points) : points, samples);
    if (closed) s = s.sublist(0, s.length - 1); // the last is (nearly) the first
    s = _smooth(s, closed: closed);
    final turns = turnsOf(s, 3, closed: closed);
    if (turns.any((t) => t.abs() > maxTurn)) return null;
    final turning = totalTurning(closed ? [...s, s.first, s[1]] : s);
    if (turning > (closed ? maxClosedTurning : maxTurning)) return null;
    if (_inflections(turns) > (closed ? maxClosedInflections : maxInflections)) return null;
    if (_crosses(s, closed: closed)) return null;
    final through = _fit(s, turns, maxError * diagonal, closed: closed);
    if (through == null) return null;
    return KappaCurve.geometry([for (final i in through) s[i]], closed: closed);
  }

  /// The samples (indices into [s]) a curve within [tolerance] of [s]
  /// passes through, fewest first; null if it takes more than the most.
  static List<int>? _fit(
    List<Offset> s,
    List<double> turns,
    double tolerance, {
    required bool closed,
  }) {
    final n = s.length, most = closed ? maxClosedPoints : maxOpenPoints;
    final picked = <int>{
      if (!closed) ...[0, n - 1],
    };
    // Where it bends most: peaks of the turning, a few samples apart.
    final peaks = [
      for (var i = 0; i < n; i++)
        if (turns[i].abs() >= minBend &&
            turns[i].abs() >= turns[(i + n - 1) % n].abs() &&
            turns[i].abs() > turns[(i + 1) % n].abs())
          i,
    ]..sort((a, b) => turns[b].abs().compareTo(turns[a].abs()));
    for (final i in peaks) {
      if (picked.every((j) => _apart(i, j, n, closed) >= 4)) picked.add(i);
    }
    // A closed curve passes through three points at least.
    for (var k = 0; closed && picked.length < 3; k++) {
      picked.add(_farthestFrom(picked, n));
    }
    if (picked.length > most) return null;
    var through = _settle(s, picked.toList()..sort(), closed: closed);
    var (error, worst) = _miss(s, through, closed: closed);
    while (error > tolerance) {
      if (through.length >= most || through.contains(worst)) return null;
      through = _settle(s, [...through, worst]..sort(), closed: closed);
      (error, worst) = _miss(s, through, closed: closed);
    }
    // Then the fewest: drop any point the curve does without.
    var dropped = true;
    while (dropped && through.length > (closed ? 3 : 2)) {
      dropped = false;
      var best = double.infinity;
      List<int>? fewer;
      for (var k = closed ? 0 : 1; k < (closed ? through.length : through.length - 1); k++) {
        final without = [...through]..removeAt(k);
        final e = _miss(s, without, closed: closed).$1;
        if (e <= dropTolerance * tolerance && e < best) (best, fewer) = (e, without);
      }
      if (fewer != null) {
        through = fewer;
        dropped = true;
      }
    }
    return through;
  }

  /// [through] (samples of [s], in order) each moved along the stroke, a
  /// few samples at a time, while that brings the curve through them closer
  /// to the stroke (mean squared distance): a point added where the curve
  /// missed most, or a bend found from noisy turning, goes where the curve
  /// fits best, so it bends there and not in a kink beside it. Open ends
  /// stay.
  static List<int> _settle(List<Offset> s, List<int> through, {required bool closed}) {
    final n = s.length;
    var best = [...through];
    var cost = _cost(s, best, closed: closed);
    for (final step in const [3, 2, 1]) {
      var moved = true;
      for (var sweep = 0; moved && sweep < 4; sweep++) {
        moved = false;
        for (var k = closed ? 0 : 1; k < (closed ? best.length : best.length - 1); k++) {
          for (final d in [-step, step]) {
            final i = best[k] + d;
            final prev = k > 0 ? best[k - 1] : (closed ? best.last - n : 0);
            final next = k + 1 < best.length ? best[k + 1] : (closed ? best.first + n : n - 1);
            if (i <= prev || i >= next) continue;
            final trial = [...best]..[k] = i % n;
            if (closed) trial.sort();
            final c = _cost(s, trial, closed: closed);
            if (c < cost) {
              (best, cost, moved) = (trial, c, true);
              break;
            }
          }
        }
      }
    }
    return best;
  }

  /// The mean squared distance of [s] from the curve through its samples
  /// [through].
  static double _cost(List<Offset> s, List<int> through, {required bool closed}) {
    final shape = KappaCurve.geometry([for (final i in through) s[i]], closed: closed);
    final line = ShapeBuilder.outline(shape, spacing: 2 * _spacing(s));
    var sum = 0.0;
    for (final p in s) {
      final d = _distance(p, line);
      sum += d * d;
    }
    return sum / s.length;
  }

  /// How far apart samples [i] and [j] of [n] are (round, if [closed]).
  static int _apart(int i, int j, int n, bool closed) {
    final d = (i - j).abs();
    return closed ? math.min(d, n - d) : d;
  }

  /// The sample farthest (round the loop) from every one of [picked].
  static int _farthestFrom(Set<int> picked, int n) {
    if (picked.isEmpty) return 0;
    var best = 0, bestGap = -1;
    for (var i = 0; i < n; i++) {
      final gap = picked.map((j) => _apart(i, j, n, true)).reduce(math.min);
      if (gap > bestGap) (best, bestGap) = (i, gap);
    }
    return best;
  }

  /// The largest distance between [s] and the curve through its samples
  /// [through] (either way), and the sample the curve misses most.
  static (double, int) _miss(List<Offset> s, List<int> through, {required bool closed}) {
    final shape = KappaCurve.geometry([for (final i in through) s[i]], closed: closed);
    final line = ShapeBuilder.outline(shape, spacing: _spacing(s));
    var error = 0.0, worst = 0;
    for (var i = 0; i < s.length; i++) {
      final d = _distance(s[i], line);
      if (d > error) (error, worst) = (d, i);
    }
    // The curve straying from the stroke (an overshoot between points).
    final ring = closed ? [...s, s.first] : s;
    for (var k = 0; k < line.length; k += 4) {
      error = math.max(error, _distance(line[k], ring));
    }
    return (error, worst);
  }

  static double _spacing(List<Offset> s) => Polyline.length(s) / (4 * s.length);

  static double _distance(Offset p, List<Offset> line) {
    var best = double.infinity;
    for (var i = 1; i < line.length; i++) {
      best = math.min(best, Polyline.distanceToSegment(p, line[i - 1], line[i]));
    }
    return best;
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
  static List<double> turnsOf(List<Offset> p, int k, {bool closed = false}) {
    final n = p.length;
    return [
      for (var i = 0; i < n; i++)
        if (!closed && (i < k || i >= n - k))
          0.0
        else
          _turn(p[i] - p[(i - k) % n], p[(i + k) % n] - p[i]),
    ];
  }

  /// [p] averaged over 5 points (fewer near an open stroke's ends, whose
  /// ends stay where they are): hand jitter out, the shape kept.
  static List<Offset> _smooth(List<Offset> p, {required bool closed}) {
    final n = p.length;
    return [
      for (var i = 0; i < n; i++)
        () {
          final k = closed ? 2 : math.min(2, math.min(i, n - 1 - i));
          var sum = Offset.zero;
          for (var j = -k; j <= k; j++) {
            sum += p[(i + j) % n];
          }
          return sum / (2 * k + 1).toDouble();
        }(),
    ];
  }

  /// How often [turns] change side, ignoring stretches nearly straight.
  static int _inflections(List<double> turns) {
    const deadBand = 4 * math.pi / 180;
    var count = 0, side = 0;
    for (final t in turns) {
      if (t.abs() < deadBand) continue;
      final s = t.sign.toInt();
      if (side != 0 && s != side) count++;
      side = s;
    }
    return count;
  }

  /// Whether polyline [p] crosses itself (a loop).
  static bool _crosses(List<Offset> p, {required bool closed}) {
    final n = closed ? p.length : p.length - 1;
    for (var i = 0; i < n; i++) {
      final a = p[i], b = p[(i + 1) % p.length];
      for (var j = i + 2; j < n; j++) {
        if (closed && i == 0 && j == n - 1) continue;
        if (_intersect(a, b, p[j], p[(j + 1) % p.length])) return true;
      }
    }
    return false;
  }

  static bool _intersect(Offset a, Offset b, Offset c, Offset d) {
    double cross(Offset o, Offset p, Offset q) =>
        (p.dx - o.dx) * (q.dy - o.dy) - (p.dy - o.dy) * (q.dx - o.dx);
    final d1 = cross(c, d, a), d2 = cross(c, d, b), d3 = cross(a, b, c), d4 = cross(a, b, d);
    return ((d1 > 0) != (d2 > 0)) &&
        ((d3 > 0) != (d4 > 0)) &&
        d1 != 0 &&
        d2 != 0 &&
        d3 != 0 &&
        d4 != 0;
  }
}
