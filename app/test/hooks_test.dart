import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:len/ink/render/growable.dart';
import 'package:len/ink/render/hooks.dart';

import 'support/handwriting.dart';

(DoubleBuffer, DoubleBuffer) _xy(List<Offset> points) {
  final x = DoubleBuffer(), y = DoubleBuffer();
  for (final p in points) {
    x.add(p.dx);
    y.add(p.dy);
  }
  return (x, y);
}

/// A straight stroke to the right, 0.9 px per sample, with a [hook] of
/// three samples landing on its start (coming from direction [angle]).
List<Offset> _landing(double angle, {double hook = 2.5}) => [
  for (var i = 3; i > 0; i--) Offset.fromDirection(angle, hook * i / 3),
  for (var i = 0; i < 30; i++) Offset(i * 0.9, 0),
];

void main() {
  final hooks = HookFinder(2.5);

  test('a pen-down flick onto the stroke is trimmed', () {
    for (final angle in [0.9, 1.6, 2.4, -1.2]) {
      final (x, y) = _xy(_landing(angle));
      expect(hooks.startCut(x, y, x.length, ended: true), 3, reason: 'angle $angle');
    }
  });

  test('a pen-up flick off the stroke is trimmed', () {
    final points = _landing(2.0).reversed.toList();
    final (x, y) = _xy(points);
    expect(hooks.endKeep(x, y, x.length), points.length - 3);
  });

  test('strokes starting or ending on a curve keep their ends, even with thick pens', () {
    for (final width in [1.5, 2.5, 4.0, 8.0]) {
      final thick = HookFinder(width);
      final hw = Handwriting();
      final shapes = {
        'o': [for (final p in hw.oval(Offset.zero, 4, 4.5)) p.offset],
        's': [for (final p in hw.letterS(Offset.zero, 9)) p.offset],
        'arc': [for (var i = 0; i < 40; i++) Offset.fromDirection(i * 0.2, 4.5)],
      };
      for (final MapEntry(key: name, value: points) in shapes.entries) {
        final (x, y) = _xy(points);
        // At most a hair (one jittery sample) may go.
        final start = thick.startCut(x, y, x.length, ended: true)!;
        // (This "s" starts with a real kink: down, then sharply left.)
        if (name != 's') {
          expect(
            (points[start] - points[0]).distance,
            lessThan(1),
            reason: '$name start, w $width',
          );
        }
        final keep = thick.endKeep(x, y, x.length);
        expect(
          (points.last - points[keep - 1]).distance,
          lessThan(1),
          reason: '$name end, w $width',
        );
      }
    }
  });

  test('a hook is a few screen pixels whatever the pen', () {
    expect(HookFinder(1).maxStart, 2);
    expect(HookFinder(20).maxStart, 3);
    expect(HookFinder(20).maxEnd, 4);
    expect(HookFinder(20, unit: 2).maxEnd, 8, reason: 'in world units at half zoom');
    expect(math.max(hooks.maxStart, hooks.maxEnd), lessThanOrEqualTo(4));
  });
}
