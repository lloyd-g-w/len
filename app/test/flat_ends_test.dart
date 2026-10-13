// Flat ends (the highlighter, the pen's flat ends) stay square over curls
// tighter than the ink's width (`FlatEnds`, INK_LAB.md "Pen end styles").
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/render/live_stroke.dart';
import 'package:len/ink/render/stroke_outline.dart';

import 'live_stroke_test.dart' show differences;
import 'support/handwriting.dart';

/// The highlighter's shape: 16 wide, stabiliser 0.5, no thinning.
const highlighter = OutlineSpec(width: 16, thinning: 0, streamline: 0.5, flatCaps: true, unit: 1);

/// Along x to (50, 0), a quarter turn of radius 2 (an eighth of the
/// width) down, then 4 more down to the end at (52, 6).
final List<StrokePoint> turn = [
  for (var x = 0.0; x < 50; x += 0.8) StrokePoint(x, 0, 0.5),
  for (var a = 0.0; a < math.pi / 2; a += 0.2)
    StrokePoint(50 + 2 * math.sin(a), 2 - 2 * math.cos(a), 0.5),
  for (var y = 2.0; y <= 6; y += 0.8) StrokePoint(52, y, 0.5),
];

/// A spiral: a full turn and more, tighter than the width.
final List<StrokePoint> curl = [
  for (var x = 0.0; x < 40; x += 0.8) StrokePoint(x, 0, 0.5),
  for (var a = 0.0; a <= 5.2; a += 0.15)
    StrokePoint(40 + 3 * math.sin(a), 3 - 3 * math.cos(a), 0.5),
];

void main() {
  test('a flat end over a turn tighter than the width is square: nothing bulges past it', () {
    for (final (name, points) in [('end', turn), ('start', turn.reversed.toList())]) {
      final path = StrokeOutline.build(points, highlighter);
      // The end's cross-section: square to where the smoothed line runs
      // over the last half radius before it (`RibbonEmitter`).
      final line = StrokeOutline.centerline(points, highlighter)!;
      final e = name == 'end' ? line.length - 1 : 0, d = name == 'end' ? -1 : 1;
      final k = (0.5 * line.r[e] / line.step).ceil();
      final c = Offset(line.x[e], line.y[e]);
      final t =
          Offset(line.x[e + d], line.y[e + d]) -
          Offset(line.x[e + (k + 1) * d], line.y[e + (k + 1) * d]);
      final along = t / t.distance;
      var across = Offset(-along.dy, along.dx);
      if (across.dx < 0) across = -across; // away from the body (x < 50)
      // Past the end, on the side away from the body, there is no ink
      // (round pieces of the turn reached 4 further); before it, there is.
      for (var u = 0.0; u <= 7; u += 0.5) {
        for (var s = 0.3; s <= 8; s += 0.5) {
          final p = c + along * s + across * u;
          expect(path.contains(p), isFalse, reason: '$name: $p');
        }
        final p = c - along * 0.3 + across * u;
        expect(path.contains(p), isTrue, reason: '$name: $p');
      }
    }
  });

  test('ink that runs past an end elsewhere stays: the body is the full width', () {
    final path = StrokeOutline.build(turn, highlighter);
    for (var x = 4.0; x <= 40; x += 1) {
      expect(path.contains(Offset(x, 7.8)), isTrue, reason: '($x, 7.8)');
      expect(path.contains(Offset(x, 8.3)), isFalse, reason: '($x, 8.3)');
    }
  });

  test('a short squiggle tighter than the width keeps its ink', () {
    final squiggle = [
      for (var a = 0.0; a <= 4 * math.pi; a += 0.2)
        StrokePoint(3 * math.cos(a) + a * 0.5, 3 * math.sin(a), 0.5),
    ];
    final path = StrokeOutline.build(squiggle, highlighter);
    for (final p in squiggle) {
      expect(path.contains(p.offset), isTrue, reason: '${p.offset}');
    }
  });

  final hw = Handwriting(seed: 5);
  final cases = {
    'turn': turn,
    'curl': curl,
    'cursive': hw.cursive(const Offset(0, 30), [e, l, l, e, u, e]),
  };
  for (final width in [2.5, 16.0]) {
    final spec = OutlineSpec(width: width, thinning: 0, streamline: 0.5, flatCaps: true, unit: 1);
    for (final MapEntry(key: name, value: points) in cases.entries) {
      test('live flat ends draw what a full build draws ($name, width $width)', () {
        final builder = LiveStrokeBuilder(spec);
        for (var n = 2; n <= points.length; n += 9) {
          final prefix = points.sublist(0, n);
          final diff = differences(
            builder.update(prefix).combined,
            StrokeOutline.build(prefix, spec, complete: false),
            spacing: 0.23,
          );
          expect(diff.length, lessThanOrEqualTo(2), reason: 'at $n points: ${diff.take(5)}');
        }
        final diff = differences(builder.finish(points), StrokeOutline.build(points, spec));
        expect(diff.length, lessThanOrEqualTo(2), reason: '${diff.take(5)}');
      });
    }
  }
}
