import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/shapes/conic_fit.dart';
import 'package:len/ink/shapes/shape_builder.dart';
import 'package:len/ink/shapes/shape_recognizer.dart';

import 'support/hand_shapes.dart';

/// Circles are circles: least-squares circle and ellipse fits, nearly
/// round hand-drawn loops snapping to true circles, and outlines that lie
/// on the curve.
void main() {
  List<Offset> arc(Offset c, double rx, double ry, double angle, {double sweep = 2 * math.pi}) => [
    for (var i = 0; i < 60; i++)
      () {
        final t = sweep * i / 60, x = rx * math.cos(t), y = ry * math.sin(t);
        return c +
            Offset(
              x * math.cos(angle) - y * math.sin(angle),
              x * math.sin(angle) + y * math.cos(angle),
            );
      }(),
  ];

  group('ConicFit', () {
    test('a circle through exact points, far from the origin, even a third of it', () {
      for (final sweep in [2 * math.pi, 2 * math.pi / 3]) {
        final fit = ConicFit.circle(arc(const Offset(10000, -5000), 37, 37, 0, sweep: sweep))!;
        expect(fit.centre.dx, closeTo(10000, 1e-6));
        expect(fit.centre.dy, closeTo(-5000, 1e-6));
        expect(fit.radius, closeTo(37, 1e-6));
      }
    });

    test('an ellipse through exact points: centre, axes and tilt', () {
      final fit = ConicFit.ellipse(arc(const Offset(300, 200), 120, 50, 0.6))!;
      expect(fit.centre.dx, closeTo(300, 1e-6));
      expect(fit.centre.dy, closeTo(200, 1e-6));
      final (major, minor, angle) = fit.rx >= fit.ry
          ? (fit.rx, fit.ry, fit.angle)
          : (fit.ry, fit.rx, fit.angle + math.pi / 2);
      expect(major, closeTo(120, 1e-6));
      expect(minor, closeTo(50, 1e-6));
      expect((angle - 0.6) % math.pi, anyOf(closeTo(0, 1e-6), closeTo(math.pi, 1e-6)));
    });

    test('points in a line fit no ellipse', () {
      expect(ConicFit.ellipse([for (var i = 0; i < 10; i++) Offset(i * 3.0, i * 2.0)]), isNull);
    });
  });

  group('hand-drawn circles', () {
    test('nearly round loops become true circles, centred where drawn', () {
      for (var seed = 0; seed < 48; seed++) {
        for (final ratio in [1.0, 0.95, 0.9]) {
          final h = HandShapes(seed);
          final pts = h.ellipse(const Offset(300, 300), 90, 90 * ratio, angle: seed * 0.37);
          final shape = ShapeRecognizer.recognize(pts)!;
          expect(shape.kind, ShapeKind.circle, reason: 'seed $seed ratio $ratio');
          final [c, rim] = shape.points;
          expect((c - const Offset(300, 300)).distance, lessThan(6), reason: 'seed $seed');
          expect((rim - c).distance, closeTo(90 * (1 + ratio) / 2, 7), reason: 'seed $seed');
        }
      }
    });

    test('clearly oval loops stay ellipses, level ones level', () {
      for (var seed = 0; seed < 48; seed++) {
        final h = HandShapes(seed);
        final tilted = ShapeRecognizer.recognize(
          h.ellipse(const Offset(300, 300), 100, 70, angle: 0.5),
        )!;
        expect(tilted.kind, ShapeKind.ellipse, reason: 'seed $seed');
        final level = ShapeRecognizer.recognize(
          h.ellipse(const Offset(300, 300), 100, 60, angle: 0.05),
        )!;
        expect(level.kind, ShapeKind.ellipse, reason: 'seed $seed');
        final [c, u, v] = level.points;
        expect((u - c).dy, 0, reason: 'seed $seed');
        expect((v - c).dx, 0, reason: 'seed $seed');
      }
    });
  });

  group('round outlines', () {
    test('points lie on the circle, about the spacing apart, at every zoom', () {
      final circle = ShapeGeometry(ShapeKind.circle, const [Offset(50, 50), Offset(250, 50)]);
      for (final spacing in [2.0, 0.5]) {
        final o = ShapeBuilder.outline(circle, spacing: spacing);
        expect(o.first, o.last);
        for (var i = 1; i < o.length; i++) {
          expect((o[i] - const Offset(50, 50)).distance, closeTo(200, 1e-9));
          expect((o[i] - o[i - 1]).distance, lessThanOrEqualTo(spacing * 1.01));
        }
      }
    });

    test('an ellipse built for a zoom has its points on the curve', () {
      final ellipse = ShapeGeometry(ShapeKind.ellipse, const [
        Offset.zero,
        Offset(120, 0),
        Offset(0, 40),
      ]);
      final pts = ShapeBuilder.pointsOf(ellipse, spacing: 0.5);
      for (final p in pts) {
        final rho = math.pow(p.x / 120, 2) + math.pow(p.y / 40, 2);
        expect(rho, closeTo(1, 1e-9));
      }
    });
  });
}
