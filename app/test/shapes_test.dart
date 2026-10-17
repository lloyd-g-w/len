import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/input/hold_to_straighten.dart';
import 'package:len/ink/shapes/polyline.dart';
import 'package:len/ink/shapes/shape_builder.dart';
import 'package:len/ink/shapes/shape_recognizer.dart';

import 'support/hand_shapes.dart';

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

/// The clean outline of what [pts] snap to.
List<Offset> outlineOf(List<Offset> pts) => ShapeBuilder.outline(ShapeRecognizer.recognize(pts)!);

void main() {
  const box = [Offset(100, 100), Offset(300, 100), Offset(300, 220), Offset(100, 220)];

  group('closed shapes', () {
    test('rectangle drawn from mid-edge with overshoot', () {
      for (var seed = 0; seed < 8; seed++) {
        final shape = ShapeRecognizer.recognize(sketch(loop(box), seed: seed))!;
        expect(shape.kind, ShapeKind.rectangle, reason: 'seed $seed');
        // Axis-aligned and close to the drawn box.
        for (final p in shape.points) {
          final nearest = box.map((c) => (c - p).distance).reduce(math.min);
          expect(nearest, lessThan(12), reason: 'seed $seed corner $p');
        }
        expect(shape.points[0].dy, shape.points[1].dy);
      }
    });

    test('a rotated rectangle stays rotated', () {
      final pts = rotated(sketch(loop(box)), 0.5, const Offset(200, 160));
      final shape = ShapeRecognizer.recognize(pts)!;
      expect(shape.kind, ShapeKind.rectangle);
      final edge = shape.points[1] - shape.points[0];
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
        final circle = outlineOf(sketch(ellipse(80, 76), seed: seed));
        final radii = circle.map((p) => (p - const Offset(200, 200)).distance);
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
        expect(shape.points, hasLength(3));
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
      expect(shape.points, hasLength(5));
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
    test('a nearly straight open stroke is a line between its ends', () {
      final pts = sketch([
        const Offset(0, 0),
        const Offset(150, 8),
        const Offset(300, 10),
      ], noise: 0.01);
      final shape = ShapeRecognizer.recognize(pts)!;
      expect(shape.kind, ShapeKind.line);
      expect(shape.points, [pts.first, pts.last]);
    });

    test('a curve, a corner or a zig-zag is no line', () {
      final arc = [
        for (var i = 0; i <= 60; i++)
          Offset(150 - 150 * math.cos(i / 60 * math.pi), -60 * math.sin(i / 60 * math.pi)),
      ];
      expect(kindOf(arc), isNull);
      expect(kindOf(sketch(const [Offset(0, 0), Offset(100, 100), Offset(200, 0)])), isNull);
      expect(
        kindOf(sketch(const [Offset(0, 0), Offset(40, 30), Offset(80, 0), Offset(120, 30)])),
        isNull,
      );
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
      expect((shape.points[1] - tip).distance, lessThan(8));
    });

    test('a hook on one side is not an arrow (nor a line)', () {
      final hooked = sketch([
        const Offset(0, 100),
        const Offset(300, 100),
        const Offset(260, 70),
      ], noise: 0.005);
      expect(kindOf(hooked), isNot(ShapeKind.arrow));
    });
  });

  group('hand-drawn samples', () {
    /// How far (at most) [shape]'s outline strays from the drawn [pts], and
    /// the drawn points from it: both close means it snapped in place, at
    /// the drawn size and rotation.
    double mismatch(ShapeGeometry shape, List<Offset> pts) {
      final outline = ShapeBuilder.outline(shape);
      double to(List<Offset> path, Offset p) =>
          [for (var i = 1; i < path.length; i++) _distanceToSegment(p, path[i - 1], path[i])]
              .reduce(math.min);
      // Past the landing hook, short of where a closing loop overshoots.
      final drawn = pts.sublist(4, pts.length - pts.length ~/ 10);
      final a = drawn.map((p) => to(outline, p)).reduce(math.max);
      final b = ShapeBuilder.points(
        outline,
        spacing: 4,
      ).map((p) => to(pts, p.offset)).reduce(math.max);
      return math.max(a, b);
    }

    test('are recognised reliably, in place', () {
      const c = Offset(300, 300);
      for (var seed = 0; seed < 48; seed++) {
        final h = HandShapes(seed);
        final tilt = seed.isEven ? 0.03 : 0.45;
        final cases = <(ShapeKind, List<Offset>)>[
          (ShapeKind.circle, h.ellipse(c, 90, 88)),
          (ShapeKind.ellipse, h.ellipse(c, 120, 60, angle: tilt)),
          (
            ShapeKind.rectangle,
            h.polygon(const [
              Offset(180, 220),
              Offset(420, 220),
              Offset(420, 380),
              Offset(180, 380),
            ], angle: tilt),
          ),
          (
            ShapeKind.triangle,
            h.polygon(const [Offset(300, 180), Offset(420, 400), Offset(180, 400)], angle: tilt),
          ),
          (
            ShapeKind.diamond,
            h.polygon(const [
              Offset(300, 170),
              Offset(410, 300),
              Offset(300, 430),
              Offset(190, 300),
            ]),
          ),
          (ShapeKind.line, h.line(const Offset(100, 200), Offset(500, 260.0 + seed * 5))),
          (ShapeKind.arrow, h.arrow(const Offset(100, 450), Offset(480, 200.0 + seed * 4))),
          // Long and thin: a bowed side or the closing overshoot is no fifth corner.
          (
            ShapeKind.rectangle,
            h.polygon(const [
              Offset(120, 250),
              Offset(480, 250),
              Offset(480, 370),
              Offset(120, 370),
            ], angle: tilt),
          ),
        ];
        for (final (kind, pts) in cases) {
          final shape = ShapeRecognizer.recognize(pts);
          expect(shape?.kind, kind, reason: '$kind, seed $seed');
          if (kind == ShapeKind.arrow) {
            expect((shape!.points[0] - pts.first).distance, lessThan(8), reason: 'seed $seed');
            continue;
          }
          // Within a few percent of the drawn size (rounded corners,
          // wobble, a gap or overshoot where the loop closes).
          final size = Polyline.bounds(pts).longestSide;
          expect(mismatch(shape!, pts), lessThan(0.08 * size), reason: '$kind, seed $seed');
        }
      }
    });

    test('handwriting never becomes a line or a shape', () {
      for (var seed = 0; seed < 8; seed++) {
        for (final word in HandShapes.writing(const Offset(100, 100), seed: seed)) {
          final shape = ShapeRecognizer.recognize(word);
          // Small closed letters ("o") are left to hold to snap's size rule.
          if (shape?.kind == ShapeKind.ellipse || shape?.kind == ShapeKind.circle) {
            expect(Polyline.bounds(word).longestSide, lessThan(HoldToStraighten.minShape));
            continue;
          }
          expect(shape, isNull, reason: 'seed $seed');
        }
      }
    });
  });

  group('ShapeBuilder', () {
    test('closed outlines end where they start and fill the dragged box', () {
      for (final kind in ShapeKind.drawable.where((k) => k.isClosed)) {
        final shape = ShapeBuilder.dragged(kind, const Offset(0, 0), const Offset(100, 60));
        final pts = ShapeBuilder.outline(shape);
        expect((pts.first - pts.last).distance, lessThan(1e-9), reason: kind.name);
        final bounds = Polyline.bounds(pts);
        expect(bounds.left, closeTo(0, 1e-6), reason: kind.name);
        expect(bounds.top, closeTo(0, 1e-6), reason: kind.name);
        expect(bounds.width, closeTo(100, 1e-6), reason: kind.name);
        expect(bounds.height, closeTo(60, 1e-6), reason: kind.name);
      }
    });

    test('points keep every vertex and constant pressure', () {
      final shape = ShapeBuilder.dragged(ShapeKind.rectangle, Offset.zero, const Offset(10, 10));
      final vertices = ShapeBuilder.outline(shape);
      final pts = ShapeBuilder.pointsOf(shape, spacing: 3, pressure: 0.7);
      for (final v in vertices) {
        expect(pts.any((p) => p.offset == v), isTrue);
      }
      expect(pts.every((p) => p.pressure == 0.7), isTrue);
      for (var i = 1; i < pts.length; i++) {
        expect((pts[i].offset - pts[i - 1].offset).distance, lessThanOrEqualTo(3 + 1e-9));
      }
    });

    test('a shape looks the same with any pen: even, round, unsmoothed', () {
      const pen = StrokeStyle(
        opacity: 0.8,
        thinning: 0.7,
        streamline: 0.4,
        unit: 0.5,
        ends: StrokeEnds.tapered,
        taperStart: 4,
        taperEnd: 6,
      );
      expect(
        ShapeBuilder.styleFor(pen.withFill(0x40FF0000)),
        const StrokeStyle(opacity: 0.8, thinning: 0, unit: 0.5).withFill(0x40FF0000),
      );
    });
  });
}

double _distanceToSegment(Offset p, Offset a, Offset b) => Polyline.distanceToSegment(p, a, b);
