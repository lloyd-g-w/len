import 'dart:math' as math;
import 'dart:ui';

/// Bézier maths for bent lines and curves: evaluating, flattening and
/// splitting cubic segments, and finding the nearest point on a spline.
abstract final class Bezier {
  /// The control point of the quadratic Bézier from [a] to [b] that passes
  /// through [mid] at t = ½.
  static Offset quadControl(Offset a, Offset mid, Offset b) => mid * 2 - (a + b) / 2;

  /// The quadratic Bézier from [a] through [mid] (at t = ½) to [b] as a
  /// polyline of at most [maxSegments] segments, its points on the curve
  /// about [spacing] (world units) apart.
  static List<Offset> quadThrough(Offset a, Offset mid, Offset b, {double spacing = 2}) {
    final c = quadControl(a, mid, b);
    final length = (c - a).distance + (b - c).distance;
    final n = (length / spacing).ceil().clamp(8, maxSegments);
    return [
      for (var i = 0; i <= n; i++)
        () {
          final t = i / n, s = 1 - t;
          return a * (s * s) + c * (2 * s * t) + b * (t * t);
        }(),
    ];
  }

  /// The most segments a flattened piece gets.
  static const int maxSegments = 1024;

  /// The cubic Bézier [a], [b], [c], [d] at [t].
  static Offset cubicAt(Offset a, Offset b, Offset c, Offset d, double t) {
    final s = 1 - t;
    return a * (s * s * s) + b * (3 * s * s * t) + c * (3 * s * t * t) + d * (t * t * t);
  }

  /// The derivative of the cubic Bézier [a], [b], [c], [d] at [t].
  static Offset cubicTangent(Offset a, Offset b, Offset c, Offset d, double t) {
    final s = 1 - t;
    return (b - a) * (3 * s * s) + (c - b) * (6 * s * t) + (d - c) * (3 * t * t);
  }

  /// How many segments of a cubic with control polygon [a]–[d] make it
  /// read as a curve at [spacing]: points on the curve about [spacing]
  /// apart (the renderer's spline through them then follows the curve at
  /// any zoom).
  static int segmentsOf(Offset a, Offset b, Offset c, Offset d, double spacing) {
    final hull = (b - a).distance + (c - b).distance + (d - c).distance;
    final chord = (d - a).distance;
    // Straight segments need one piece; bends more, by how much they bow.
    if (hull - chord <= 1e-9 * (hull + 1)) return 1;
    return ((hull + chord) / (2 * spacing)).ceil().clamp(6, maxSegments);
  }

  /// The segments of spline [points] (anchor, out, in, anchor, …; closed
  /// when [closed], the last point then being the first anchor's in
  /// handle), each as its four control points.
  static List<List<Offset>> segments(List<Offset> points, {required bool closed}) {
    final n = closed ? points.length ~/ 3 : (points.length - 1) ~/ 3;
    return [
      for (var i = 0; i < n; i++)
        [points[3 * i], points[3 * i + 1], points[3 * i + 2], points[(3 * i + 3) % points.length]],
    ];
  }

  /// Spline [points] as a polyline (closed ones end where they start),
  /// with every anchor on it exactly.
  static List<Offset> flatten(List<Offset> points, {required bool closed, double spacing = 2}) {
    final out = <Offset>[points.first];
    for (final [a, b, c, d] in segments(points, closed: closed)) {
      final n = segmentsOf(a, b, c, d, spacing);
      for (var k = 1; k < n; k++) {
        out.add(cubicAt(a, b, c, d, k / n));
      }
      out.add(d);
    }
    return out;
  }

  /// The nearest point of spline [points] to [p]: its segment, parameter
  /// and distance.
  static ({int segment, double t, double distance}) nearest(
    List<Offset> points,
    Offset p, {
    required bool closed,
  }) {
    var best = (segment: 0, t: 0.0, distance: double.infinity);
    for (final (i, [a, b, c, d]) in segments(points, closed: closed).indexed) {
      // Coarse samples, then a few rounds of bisection around the best.
      const samples = 32;
      var bestT = 0.0, bestD = double.infinity;
      for (var k = 0; k <= samples; k++) {
        final d2 = (cubicAt(a, b, c, d, k / samples) - p).distance;
        if (d2 < bestD) {
          bestD = d2;
          bestT = k / samples;
        }
      }
      var step = 1 / samples;
      for (var round = 0; round < 12; round++) {
        step /= 2;
        for (final t in [bestT - step, bestT + step]) {
          if (t < 0 || t > 1) continue;
          final d2 = (cubicAt(a, b, c, d, t) - p).distance;
          if (d2 < bestD) {
            bestD = d2;
            bestT = t;
          }
        }
      }
      if (bestD < best.distance) best = (segment: i, t: bestT, distance: bestD);
    }
    return best;
  }

  /// Spline [points] with an anchor added on segment [segment] at [t],
  /// splitting it (de Casteljau) so the outline stays the same.
  static List<Offset> split(List<Offset> points, int segment, double t, {required bool closed}) {
    final i = 3 * segment;
    final a = points[i], b = points[i + 1], c = points[i + 2];
    final d = points[(i + 3) % points.length];
    final ab = Offset.lerp(a, b, t)!, bc = Offset.lerp(b, c, t)!, cd = Offset.lerp(c, d, t)!;
    final abc = Offset.lerp(ab, bc, t)!, bcd = Offset.lerp(bc, cd, t)!;
    final mid = Offset.lerp(abc, bcd, t)!;
    return [...points.sublist(0, i + 1), ab, abc, mid, bcd, cd, ...points.sublist(i + 3)];
  }

  /// Spline [points] without anchor [anchor] (and its handles); the
  /// neighbouring segments join into one.
  static List<Offset> removeAnchor(List<Offset> points, int anchor, {required bool closed}) {
    final i = 3 * anchor;
    if (!closed && anchor == 0) return points.sublist(3);
    if (!closed && i == points.length - 1) return points.sublist(0, points.length - 3);
    if (closed && anchor == 0) {
      // Keep anchor 0 first: the old last anchor's segment runs on to anchor 1.
      return [...points.sublist(3, points.length - 1), points[2]];
    }
    return [...points.sublist(0, i - 1), ...points.sublist(i + 2)];
  }

  /// The angle (radians, in [0, π]) between [a] and [b].
  static double angleBetween(Offset a, Offset b) {
    final la = a.distance, lb = b.distance;
    if (la == 0 || lb == 0) return 0;
    final cos = ((a.dx * b.dx + a.dy * b.dy) / (la * lb)).clamp(-1.0, 1.0);
    return math.acos(cos);
  }
}
