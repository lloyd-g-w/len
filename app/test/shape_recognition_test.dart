import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/shape_geometry.dart';
import 'package:len/ink/shapes/conic_fit.dart';
import 'package:len/ink/shapes/shape_recognizer.dart';

import 'support/hand_shapes.dart';

double _side(ShapeGeometry s, int i) =>
    (s.points[(i + 1) % s.points.length] - s.points[i]).distance;

void main() {
  test('a nearly square rectangle is a square; an oblong one stays', () {
    for (var seed = 0; seed < 12; seed++) {
      final h = HandShapes(seed);
      final square = ShapeRecognizer.recognize(
        h.polygon(const [Offset(100, 100), Offset(300, 100), Offset(300, 288), Offset(100, 288)]),
      )!;
      expect(square.kind, ShapeKind.rectangle, reason: 'seed $seed');
      expect(_side(square, 0), closeTo(_side(square, 1), 1e-6), reason: 'seed $seed');
      final oblong = ShapeRecognizer.recognize(
        h.polygon(const [Offset(100, 100), Offset(300, 100), Offset(300, 240), Offset(100, 240)]),
      )!;
      expect(oblong.kind, ShapeKind.rectangle);
      expect((_side(oblong, 0) / _side(oblong, 1) - 200 / 140).abs(), lessThan(0.15));
    }
  });

  test('a nearly equilateral triangle is equilateral, its base level', () {
    for (var seed = 0; seed < 12; seed++) {
      final h = HandShapes(seed);
      // 3° off level, sides 200, 196, 204-ish.
      final drawn = h.polygon(const [
        Offset(300, 127),
        Offset(400, 300),
        Offset(198, 296),
      ], angle: 0.05);
      final tri = ShapeRecognizer.recognize(drawn)!;
      expect(tri.kind, ShapeKind.triangle, reason: 'seed $seed');
      for (var i = 0; i < 3; i++) {
        expect(_side(tri, i), closeTo(_side(tri, 0), 1e-6), reason: 'seed $seed');
      }
      final ys = [for (final p in tri.points) p.dy]..sort();
      expect(ys[2] - ys[1], lessThan(1e-6), reason: 'seed $seed: a level base');
    }
  });

  test('a clearly scalene, tilted triangle stays as drawn', () {
    final tri = ShapeRecognizer.recognize(
      HandShapes(3).polygon(const [Offset(200, 100), Offset(420, 300), Offset(150, 260)]),
    )!;
    expect(tri.kind, ShapeKind.triangle);
    expect((_side(tri, 0) - _side(tri, 1)).abs(), greaterThan(20));
  });

  test('ellipses are fitted to the loop, not to its bumps', () {
    const c = Offset(300, 300);
    for (var seed = 0; seed < 24; seed++) {
      final pts = HandShapes(seed).ellipse(c, 140, 70, angle: 0.4);
      final e = ConicFit.ellipse(pts)!;
      expect((e.centre - c).distance, lessThan(8), reason: 'seed $seed');
      final (major, minor) = e.rx > e.ry ? (e.rx, e.ry) : (e.ry, e.rx);
      expect(major, closeTo(140, 10), reason: 'seed $seed');
      expect(minor, closeTo(70, 7), reason: 'seed $seed');
      // A bump (a stroke that wobbles out on one side) barely moves it.
      final bumped = [
        for (final (i, p) in pts.indexed)
          i > pts.length * 0.3 && i < pts.length * 0.36 ? c + (p - c) * 1.12 : p,
      ];
      final b = ConicFit.ellipse(bumped)!;
      expect((b.centre - c).distance, lessThan(10), reason: 'seed $seed');
      expect(math.max(b.rx, b.ry), lessThan(155), reason: 'seed $seed');
    }
  });
}
