import 'dart:math' as math;
import 'dart:ui';

import '../../domain/shape_geometry.dart';
import 'curve_fit.dart';
import 'polyline.dart';
import 'shape_recognizer.dart';

/// Recognises a held stroke that is no other shape as a smooth curve: a
/// cubic spline fitted to it ([CurveFit]) with few anchors. Only smooth
/// strokes qualify, and handwriting is not smooth: no corner (no turn
/// sharper than [maxTurn] over a few points: letters' cusps and
/// zig-zags), no loop (no crossing: "e", "l"), at most [maxTurning] of
/// turning in all and [maxInflections] changes of direction (no waves,
/// no spirals), and a fit within [maxError] of the stroke by a handful
/// of anchors ([maxOpenAnchors], [maxClosedAnchors]). Hold to snap also
/// requires a size ([HoldToStraighten.minCurve]).
abstract final class CurveRecognizer {
  /// Points the stroke is resampled to.
  static const int samples = 64;

  /// The sharpest turn allowed over 3 samples each side (radians, 60°).
  static const double maxTurn = 60 * math.pi / 180;

  /// The most turning in all (radians), open and closed.
  static const double maxTurning = 2 * math.pi, maxClosedTurning = 4 * math.pi;

  /// The most changes between turning left and right, open and closed.
  static const int maxInflections = 2, maxClosedInflections = 4;

  /// The fit's largest distance from the stroke, relative to its
  /// bounding-box diagonal.
  static const double maxError = 0.02;

  static const int maxOpenAnchors = 5, maxClosedAnchors = 6;

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
    final turns = CurveFit.turns(s, 3, closed: closed);
    if (turns.any((t) => t.abs() > maxTurn)) return null;
    final turning = CurveFit.totalTurning(closed ? [...s, s.first, s[1]] : s);
    if (turning > (closed ? maxClosedTurning : maxTurning)) return null;
    if (_inflections(turns) > (closed ? maxClosedInflections : maxInflections)) return null;
    if (_crosses(s, closed: closed)) return null;
    final spline = CurveFit.fit(s, maxError * diagonal, closed: closed);
    final curve = ShapeGeometry(ShapeKind.curve, spline);
    if (curve.anchorCount > (closed ? maxClosedAnchors : maxOpenAnchors)) return null;
    return curve;
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
