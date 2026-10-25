import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/shapes/bezier.dart';
import 'package:len/ink/shapes/kappa_curve.dart';
import 'package:len/ink/shapes/polyline.dart';
import 'package:len/ink/shapes/shape_builder.dart';

/// κ-curves: through every point, bending most there, smooth between.
void main() {
  Offset quadAt(List<Offset> q, double t) =>
      q[0] * ((1 - t) * (1 - t)) + q[1] * (2 * t * (1 - t)) + q[2] * (t * t);

  double curvature(List<Offset> q, double t) {
    final d1 = (q[1] - q[0]) * (2 * (1 - t)) + (q[2] - q[1]) * (2 * t);
    final d2 = (q[2] - q[1] * 2 + q[0]) * 2;
    return (d1.dx * d2.dy - d1.dy * d2.dx) / math.pow(d1.distance, 3);
  }

  /// The distance from [p] to the curve made of [quads].
  double off(List<List<Offset>> quads, Offset p) {
    var best = double.infinity;
    for (final q in quads) {
      for (var k = 0; k <= 2000; k++) {
        best = math.min(best, (quadAt(q, k / 2000) - p).distance);
      }
    }
    return best;
  }

  const wave = [Offset(0, 100), Offset(80, 0), Offset(160, 90), Offset(240, 10), Offset(320, 80)];
  const blob = [Offset(0, 0), Offset(120, -20), Offset(160, 70), Offset(60, 120), Offset(-20, 60)];

  test('an open curve passes through every point, its pieces meeting smoothly', () {
    final quads = KappaCurve.quadratics(wave, closed: false);
    expect(quads.length, wave.length - 2);
    expect(quads.first.first, wave.first);
    expect(quads.last.last, wave.last);
    for (final p in wave) {
      expect(off(quads, p), lessThan(0.05), reason: '$p');
    }
    for (var i = 1; i < quads.length; i++) {
      final a = quads[i - 1], b = quads[i];
      expect(a[2], b[0]);
      // G¹: the join lies on the segment between the two middle points.
      final cross = (a[1] - a[2]).dx * (b[1] - a[2]).dy - (a[1] - a[2]).dy * (b[1] - a[2]).dx;
      expect(cross.abs(), lessThan(1e-6 * (a[1] - b[1]).distanceSquared));
    }
  });

  test('each piece bends most at its point (no bumps between points)', () {
    for (final (points, closed) in [(wave, false), (blob, true)]) {
      final quads = KappaCurve.quadratics(points, closed: closed);
      final inner = closed ? points : points.sublist(1, points.length - 1);
      for (final (i, q) in quads.indexed) {
        var peak = 0.0, at = 0.0;
        for (var k = 0; k <= 1000; k++) {
          final c = curvature(q, k / 1000).abs();
          if (c > peak) (peak, at) = (c, k / 1000);
        }
        expect((quadAt(q, at) - inner[i]).distance, lessThan(1.5), reason: 'piece $i');
      }
    }
  });

  test('curvature matches across joins where the curve does not inflect (G²)', () {
    final quads = KappaCurve.quadratics(blob, closed: true);
    for (var i = 0; i < quads.length; i++) {
      final a = quads[i], b = quads[(i + 1) % quads.length];
      expect(curvature(a, 1), closeTo(curvature(b, 0), 1e-3 * curvature(a, 1).abs() + 1e-6));
    }
  });

  test('a closed curve loops through every point, far from the origin too', () {
    final far = [for (final p in blob) p + const Offset(1e5, -3e4)];
    final quads = KappaCurve.quadratics(far, closed: true);
    expect(quads.length, blob.length);
    expect(quads.last.last, quads.first.first);
    for (final p in far) {
      expect(off(quads, p), lessThan(0.05));
    }
  });

  test('corners split the curve: straight on from a corner, sharp there', () {
    const points = [Offset(0, 0), Offset(100, 0), Offset(100, 100), Offset(0, 100)];
    final shape = KappaCurve.geometry(points, closed: false, corners: [1, 2]);
    // Two points between corners: a straight piece.
    final o = ShapeBuilder.outline(shape);
    for (final p in o) {
      final onSide = [
        Polyline.distanceToSegment(p, points[0], points[1]),
        Polyline.distanceToSegment(p, points[1], points[2]),
        Polyline.distanceToSegment(p, points[2], points[3]),
      ].reduce(math.min);
      expect(onSide, lessThan(1e-9));
    }
    expect(shape.through, points);
    expect(shape.corners, [1, 2]);
  });

  test('a zig-zag of points makes no loops', () {
    const zig = [
      Offset(0, 0),
      Offset(50, 90),
      Offset(100, 10),
      Offset(170, 100),
      Offset(200, 0),
      Offset(300, 20),
    ];
    final shape = KappaCurve.geometry(zig, closed: false);
    final o = Bezier.flatten(shape.points, closed: false, spacing: 0.5);
    // No crossing.
    bool crosses(Offset a, Offset b, Offset c, Offset d) {
      double x(Offset o, Offset p, Offset q) =>
          (p.dx - o.dx) * (q.dy - o.dy) - (p.dy - o.dy) * (q.dx - o.dx);
      return (x(c, d, a) > 0) != (x(c, d, b) > 0) && (x(a, b, c) > 0) != (x(a, b, d) > 0);
    }

    for (var i = 0; i + 1 < o.length; i++) {
      for (var j = i + 2; j + 1 < o.length; j++) {
        expect(crosses(o[i], o[i + 1], o[j], o[j + 1]), isFalse, reason: '$i, $j');
      }
    }
  });

  test('the spline is the quadratics exactly, as cubics', () {
    final quads = KappaCurve.quadratics(blob, closed: true);
    final spline = KappaCurve.spline(blob, closed: true);
    expect(spline.length, 3 * blob.length);
    for (final (i, q) in quads.indexed) {
      final [a, b, c, d] = Bezier.segments(spline, closed: true)[i];
      for (final t in [0.1, 0.37, 0.8]) {
        expect((Bezier.cubicAt(a, b, c, d, t) - quadAt(q, t)).distance, lessThan(1e-9));
      }
    }
  });

  test('stored and read back, through points and corners stay', () {
    final shape = KappaCurve.geometry(wave, closed: false, corners: [2]);
    final back = ShapeGeometry.fromJson(shape.toJson());
    expect(back, shape);
    expect(back.passesThrough, isTrue);
    // A plain spline (stored before curves passed through points) reads as one.
    final plain = ShapeGeometry(ShapeKind.curve, shape.points);
    expect(ShapeGeometry.fromJson(plain.toJson()).through, isNull);
    expect(
      () => ShapeGeometry.fromJson({
        ...shape.toJson(),
        'c': [5, 2],
      }),
      throwsFormatException,
    );
  });
}
