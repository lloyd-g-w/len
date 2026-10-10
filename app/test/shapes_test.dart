import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/ink/shapes/shape_builder.dart';
import 'package:len/ink/shapes/shape_kind.dart';
import 'package:len/ink/shapes/shape_recognizer.dart';

/// Hand-drawn-like samples along [vertices]: ~3 units apart, with a slow
/// wobble and jitter of about [noise] of the shape's size.
List<Offset> sketch(List<Offset> vertices, {double noise = 0.015, int seed = 1}) {
  final random = math.Random(seed);
  final size = Rect.fromPoints(vertices.first, vertices[vertices.length ~/ 2]).longestSide;
  final out = <Offset>[];
  var phase = random.nextDouble() * 6;
  for (var i = 1; i < vertices.length; i++) {
    final a = vertices[i - 1], b = vertices[i];
    final steps = math.max(2, ((b - a).distance / 3).ceil());
    for (var k = 0; k < steps; k++) {
      final p = Offset.lerp(a, b, k / steps)!;
      phase += 0.08;
      final wobble = Offset(math.sin(phase), math.cos(phase * 1.3)) * (noise * size * 0.6);
      final jitter = Offset(random.nextDouble() - 0.5, random.nextDouble() - 0.5) * (noise * size);
      out.add(p + wobble + jitter);
    }
  }
  out.add(vertices.last);
  return out;
}

List<Offset> rotated(List<Offset> pts, double angle, Offset pivot) => [
  for (final p in pts)
    pivot +
        Offset(
          (p - pivot).dx * math.cos(angle) - (p - pivot).dy * math.sin(angle),
          (p - pivot).dx * math.sin(angle) + (p - pivot).dy * math.cos(angle),
        ),
];

/// A closed loop that starts at fraction [start] of the way along the
/// first edge and overshoots its start a little (as people draw).
List<Offset> loop(List<Offset> corners, {double start = 0.4, double overshoot = 0.15}) {
  final first = Offset.lerp(corners[0], corners[1], start)!;
  final past = Offset.lerp(corners[0], corners[1], start + overshoot)!;
  return [first, ...corners.skip(1), corners[0], past];
}

ShapeKind? kindOf(List<Offset> pts) => ShapeRecognizer.recognize(pts)?.kind;

void main() {
  const box = [Offset(100, 100), Offset(300, 100), Offset(300, 220), Offset(100, 220)];

  group('closed shapes', () {
    test('rectangle drawn from mid-edge with overshoot', () {
      for (var seed = 0; seed < 8; seed++) {
        final shape = ShapeRecognizer.recognize(sketch(loop(box), seed: seed))!;
        expect(shape.kind, ShapeKind.rectangle, reason: 'seed $seed');
        // Axis-aligned, close to the drawn box, and closed.
        expect(shape.outline.first, shape.outline.last);
        for (final p in shape.outline) {
          final nearest = box.map((c) => (c - p).distance).reduce(math.min);
          expect(nearest, lessThan(12), reason: 'seed $seed corner $p');
        }
        expect(shape.outline[0].dy, shape.outline[1].dy);
      }
    });

    test('a rotated rectangle stays rotated', () {
      final pts = rotated(sketch(loop(box)), 0.5, const Offset(200, 160));
      final shape = ShapeRecognizer.recognize(pts)!;
      expect(shape.kind, ShapeKind.rectangle);
      final edge = shape.outline[1] - shape.outline[0];
      final angle = math.atan2(edge.dy, edge.dx);
      final mod = (angle % (math.pi / 2) + math.pi / 2) % (math.pi / 2);
      expect(mod, closeTo(0.5, 0.06));
    });

    test('circle and rotated ellipse', () {
      List<Offset> ellipse(double rx, double ry) => [
        for (var i = 0; i <= 80; i++)
          Offset(
            200 + rx * math.cos(i / 80 * 2.1 * math.pi),
            200 + ry * math.sin(i / 80 * 2.1 * math.pi),
          ),
      ];
      for (var seed = 0; seed < 5; seed++) {
        final circle = ShapeRecognizer.recognize(sketch(ellipse(80, 76), seed: seed))!;
        expect(circle.kind, ShapeKind.ellipse, reason: 'seed $seed');
        final radii = circle.outline.map((p) => (p - const Offset(200, 200)).distance);
        expect(radii.reduce(math.max) - radii.reduce(math.min), lessThan(8)); // a circle
      }
      final tilted = rotated(sketch(ellipse(120, 50)), 0.6, const Offset(200, 200));
      expect(kindOf(tilted), ShapeKind.ellipse);
    });

    test('triangle and pentagon', () {
      const tri = [Offset(200, 50), Offset(320, 250), Offset(80, 250)];
      for (var seed = 0; seed < 5; seed++) {
        final shape = ShapeRecognizer.recognize(sketch(loop(tri), seed: seed))!;
        expect(shape.kind, ShapeKind.triangle, reason: 'seed $seed');
        expect(shape.outline, hasLength(4));
      }
      final pentagon = [
        for (var i = 0; i < 5; i++)
          const Offset(200, 200) +
              Offset(
                    math.cos(i * 2 * math.pi / 5 - math.pi / 2),
                    math.sin(i * 2 * math.pi / 5 - math.pi / 2),
                  ) *
                  120,
      ];
      final shape = ShapeRecognizer.recognize(sketch(loop(pentagon)))!;
      expect(shape.kind, ShapeKind.polygon);
      expect(shape.outline, hasLength(6));
    });

    test('a skewed quadrilateral is a polygon, not a rectangle', () {
      const quad = [Offset(100, 100), Offset(300, 100), Offset(380, 260), Offset(180, 260)];
      expect(kindOf(sketch(loop(quad))), ShapeKind.polygon);
    });

    test('scribbles are not recognised', () {
      final random = math.Random(7);
      var p = const Offset(200, 200);
      final scribble = <Offset>[p];
      for (var i = 0; i < 300; i++) {
        p += Offset(random.nextDouble() * 30 - 15, random.nextDouble() * 30 - 15);
        scribble.add(p);
      }
      scribble.add(const Offset(202, 201));
      expect(kindOf(scribble), isNull);
    });
  });

  group('open shapes', () {
    test('a wobbly open stroke is a line between its ends', () {
      final pts = sketch([
        const Offset(0, 0),
        const Offset(150, 40),
        const Offset(300, 10),
      ], noise: 0.03);
      final shape = ShapeRecognizer.recognize(pts)!;
      expect(shape.kind, ShapeKind.line);
      expect(shape.outline, [pts.first, pts.last]);
    });

    test('an arrow: shaft then both wings', () {
      const tip = Offset(300, 100);
      final drawn = sketch([
        const Offset(0, 100),
        tip,
        const Offset(260, 70),
        tip + const Offset(-2, 1),
        const Offset(258, 132),
      ], noise: 0.005);
      final shape = ShapeRecognizer.recognize(drawn)!;
      expect(shape.kind, ShapeKind.arrow);
      expect((shape.outline[1] - tip).distance, lessThan(8));
    });

    test('a hook on one side is not an arrow', () {
      final hooked = sketch([
        const Offset(0, 100),
        const Offset(300, 100),
        const Offset(260, 70),
      ], noise: 0.005);
      expect(kindOf(hooked), ShapeKind.line);
    });
  });

  group('ShapeBuilder', () {
    test('closed outlines end where they start', () {
      for (final kind in ShapeKind.drawable.where((k) => k.isClosed)) {
        final pts = ShapeBuilder.outline(kind, const Offset(0, 0), const Offset(100, 60));
        expect((pts.first - pts.last).distance, lessThan(1e-9), reason: kind.name);
        final b = Rect.fromPoints(pts.first, pts.first);
        final bounds = pts.fold(b, (r, p) => r.expandToInclude(Rect.fromPoints(p, p)));
        expect(bounds.width, closeTo(100, 1e-6), reason: kind.name);
        expect(bounds.height, closeTo(60, 1e-6), reason: kind.name);
      }
    });

    test('points keep every vertex and constant pressure', () {
      final vertices = ShapeBuilder.outline(ShapeKind.rectangle, Offset.zero, const Offset(10, 10));
      final pts = ShapeBuilder.points(vertices, spacing: 3, pressure: 0.7);
      for (final v in vertices) {
        expect(pts.any((p) => p.offset == v), isTrue);
      }
      expect(pts.every((p) => p.pressure == 0.7), isTrue);
      for (var i = 1; i < pts.length; i++) {
        expect((pts[i].offset - pts[i - 1].offset).distance, lessThanOrEqualTo(3 + 1e-9));
      }
    });
  });
}
