import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/shape_geometry.dart';
import 'package:len/ink/shapes/shape_builder.dart';
import 'package:len/ink/shapes/shape_snap.dart';

/// Pen snaps without Shift: lines level / upright / diagonal, shapes regular.
void main() {
  const o = Offset(100, 100);
  Offset at(double degrees, double r) => o + Offset.fromDirection(degrees * math.pi / 180, r);

  test('a line within 4° of level, upright or diagonal snaps; others stay', () {
    expect(ShapeSnap.lineEnd(o, at(2, 300)), o + const Offset(300, 0));
    expect(ShapeSnap.lineEnd(o, at(-3.5, 300)), o + const Offset(300, 0));
    expect(ShapeSnap.lineEnd(o, at(91, 200)), o + const Offset(0, 200));
    expect(ShapeSnap.lineEnd(o, at(-88, 200)), o + const Offset(0, -200));
    final back = ShapeSnap.lineEnd(o, at(181, 50));
    expect(back.dy, 100);
    expect(back.dx, closeTo(50, 1e-9));
    final diagonal = ShapeSnap.lineEnd(o, at(47, 100)) - o;
    expect(diagonal.direction, closeTo(math.pi / 4, 1e-9));
    expect(diagonal.distance, closeTo(100, 1e-9));
    for (final free in [6.0, 20.0, 30.0, 60.0, -15.0]) {
      expect(ShapeSnap.lineEnd(o, at(free, 200)), at(free, 200), reason: '$free°');
    }
    expect(ShapeSnap.lineEnd(o, o), o);
  });

  test('a nearly regular drag becomes regular; a clearly oblong one stays', () {
    expect(
      ShapeSnap.dragEnd(ShapeKind.rectangle, o, o + const Offset(205, 195)),
      o + const Offset(200, 200),
    );
    expect(
      ShapeSnap.dragEnd(ShapeKind.ellipse, o, o + const Offset(-104, 100)),
      o + const Offset(-102, 102),
    );
    expect(
      ShapeSnap.dragEnd(ShapeKind.rectangle, o, o + const Offset(230, 200)),
      o + const Offset(230, 200),
    );
    // An equilateral triangle's box is wider than tall.
    final aspect = ShapeBuilder.regularAspect(ShapeKind.triangle);
    final end = ShapeSnap.dragEnd(ShapeKind.triangle, o, o + Offset(100 * aspect + 3, 100));
    expect((end - o).dx / (end - o).dy, closeTo(aspect, 1e-9));
    // Lines snap by angle.
    expect(ShapeSnap.dragEnd(ShapeKind.arrow, o, at(1, 100)), o + const Offset(100, 0));
  });

  test('a corner nearly square snaps, along the shape\'s own sides', () {
    expect(ShapeSnap.squareCorner(o, o + const Offset(104, 100), 0), o + const Offset(102, 102));
    expect(ShapeSnap.squareCorner(o, o + const Offset(150, 100), 0), o + const Offset(150, 100));
    // Turned by 30°: a near square in its frame becomes a square in it.
    const angle = math.pi / 6;
    Offset turned(double x, double y) =>
        o +
        Offset(
          x * math.cos(angle) - y * math.sin(angle),
          x * math.sin(angle) + y * math.cos(angle),
        );
    final snapped = ShapeSnap.squareCorner(o, turned(97, 100), angle);
    expect((snapped - turned(98.5, 98.5)).distance, lessThan(1e-9));
  });

  test('arrowheads keep one size on long arrows, smaller on short ones', () {
    double head(double length) {
      final o = ShapeBuilder.arrow(Offset.zero, Offset(length, 0));
      return (o[2] - o[1]).distance;
    }

    expect(head(400), closeTo(ShapeBuilder.maxHead, 1e-9));
    expect(head(150), closeTo(ShapeBuilder.maxHead, 1e-9));
    expect(head(80), closeTo(80 * 0.18, 1e-9));
    expect(head(40), closeTo(ShapeBuilder.minHead, 1e-9));
    expect(head(20), closeTo(8, 1e-9));
  });
}
