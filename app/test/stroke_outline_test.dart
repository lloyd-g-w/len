import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/render/stroke_outline.dart';

const spec = OutlineSpec(width: 8, thinning: 0.9, streamline: 0.4);

/// A horizontal stroke at medium pressure from x=0 to x=100.
List<StrokePoint> line({double endPressure = 0.5, List<Offset> tail = const []}) => [
  for (var x = 0.0; x <= 100; x += 4) StrokePoint(x, 50, 0.5),
  for (final t in tail) StrokePoint(t.dx, t.dy, endPressure),
];

/// Vertical extent of the outline within [x0, x1].
double heightNear(Path path, double x0, double x1) {
  var top = double.infinity, bottom = double.negativeInfinity;
  for (var x = x0; x <= x1; x += 0.25) {
    for (var y = 30.0; y <= 70; y += 0.1) {
      if (path.contains(Offset(x, y))) {
        if (y < top) top = y;
        if (y > bottom) bottom = y;
      }
    }
  }
  return bottom - top;
}

void main() {
  test('a uniform stroke is as wide as its nominal width', () {
    final path = StrokeOutline.build(line(), spec);
    expect(heightNear(path, 40, 60), closeTo(8, 0.5));
  });

  test('a pressure spike at pen-up does not leave a blob at the end', () {
    final path = StrokeOutline.build(
      line(endPressure: 1, tail: const [Offset(101, 50), Offset(102, 50)]),
      spec,
    );
    final body = heightNear(path, 60, 80);
    expect(heightNear(path, 95, 106), lessThanOrEqualTo(body + 0.3));
  });

  test('a lift hook doubling back is trimmed', () {
    final path = StrokeOutline.build(
      line(tail: const [Offset(101, 52), Offset(99, 54), Offset(97, 55)]),
      spec,
    );
    // The hook would add width below the line near its end.
    expect(path.getBounds().bottom, lessThan(54.5 + 0.1));
  });

  test('sharp corners keep full width (no pinch)', () {
    final points = [
      for (var x = 0.0; x <= 60; x += 3) StrokePoint(x, 50, 0.5),
      for (var y = 53.0; y <= 110; y += 3) const StrokePoint(60, 0, 0.5).copyWithY(y),
    ];
    final path = StrokeOutline.build(points, spec);
    expect(path.contains(const Offset(58, 50)), isTrue);
    expect(path.contains(const Offset(60, 56)), isTrue);
    // Full width on both legs right up to the (stabiliser-rounded) corner.
    expect(heightNear(path, 50, 54), closeTo(8, 0.6));
    expect(path.getBounds().right, greaterThan(63.5));
  });

  test('a tap renders a dot', () {
    final path = StrokeOutline.build(const [StrokePoint(5, 5, 0.5)], spec);
    expect(path.contains(const Offset(5, 5)), isTrue);
    expect(path.getBounds().width, closeTo(8, 0.5));
  });

  test('a tiny back-and-forth stays where it was written, stabilised or not', () {
    // A 1 px flick down and back, and a jitter at a cusp: short stretches
    // between corners once continued a quadratic through a few samples
    // past their ends and flung the line pen-widths away.
    const flick = [
      StrokePoint(0, 0, 0.5),
      StrokePoint(-0.25, -1.14, 0.5),
      StrokePoint(0.14, 0, 0.5),
    ];
    const cusp = [
      StrokePoint(0, 0, 0.5),
      StrokePoint(2.45, 0.63, 0.5),
      StrokePoint(4.52, 1.64, 0.5),
      StrokePoint(5.9, 2.64, 0.5),
      StrokePoint(7.6, 4.36, 0.5),
      StrokePoint(6.86, 3.44, 0.5),
      StrokePoint(7.56, 4.32, 0.5),
      StrokePoint(6.52, 2.58, 0.5),
      StrokePoint(6.09, 1.97, 0.5),
      StrokePoint(5, -0.52, 0.5),
      StrokePoint(5.95, 1.28, 0.5),
      StrokePoint(5.55, 0.08, 0.5),
    ];
    for (final points in [flick, cusp]) {
      final box = Rect.fromPoints(
        Offset(points.map((p) => p.x).reduce(math.min), points.map((p) => p.y).reduce(math.min)),
        Offset(points.map((p) => p.x).reduce(math.max), points.map((p) => p.y).reduce(math.max)),
      );
      for (final streamline in [0.0, 0.5, 1.0]) {
        final s = OutlineSpec(width: 5, thinning: 0.5, streamline: streamline, unit: 1);
        final line = StrokeOutline.centerline(points, s)!;
        for (var i = 0; i < line.x.length; i++) {
          expect(
            box.inflate(0.5).contains(Offset(line.x[i], line.y[i])),
            isTrue,
            reason: 'streamline $streamline: (${line.x[i]}, ${line.y[i]}) outside $box',
          );
        }
      }
    }
  });
}

extension on StrokePoint {
  StrokePoint copyWithY(double y) => StrokePoint(x, y, pressure);
}
