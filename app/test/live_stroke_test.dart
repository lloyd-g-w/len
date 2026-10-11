import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/render/live_stroke.dart';
import 'package:len/ink/render/stroke_outline.dart';

import 'support/handwriting.dart';

/// Points where [a] and [b] disagree on a grid over their bounds.
List<Offset> differences(Path a, Path b, {double spacing = 0.11}) {
  final bounds = a.getBounds().expandToInclude(b.getBounds()).inflate(0.5);
  final out = <Offset>[];
  for (var y = bounds.top; y <= bounds.bottom; y += spacing) {
    for (var x = bounds.left; x <= bounds.right; x += spacing) {
      final p = Offset(x, y);
      if (a.contains(p) != b.contains(p)) out.add(p);
    }
  }
  return out;
}

void main() {
  final hw = Handwriting(seed: 7);
  final strokes = {
    'cursive': hw.cursive(const Offset(0, 30), [e, l, l, e, u, e]),
    'zigzag': [
      for (var i = 0; i <= 60; i++)
        StrokePoint(i * 0.8, (i ~/ 10).isEven ? (i % 10) * 2.0 : 20 - (i % 10) * 2.0, 0.5),
    ],
    'line': [for (var i = 0; i <= 200; i++) StrokePoint(i * 0.7, 0.05 * math.sin(i * 1.3), 0.5)],
  };

  for (final streamline in [0.0, 0.4, 1.0]) {
    final spec = OutlineSpec(width: 2.5, thinning: 0.25, streamline: streamline);
    for (final MapEntry(key: name, value: points) in strokes.entries) {
      test('the live builder draws what a full rebuild draws ($name @ $streamline)', () {
        final builder = LiveStrokeBuilder(spec);
        for (var n = 2; n <= points.length; n += 7) {
          final prefix = points.sublist(0, n);
          final live = builder.update(prefix).combined;
          final full = StrokeOutline.build(prefix, spec, complete: false);
          final diff = differences(live, full);
          expect(diff.length, lessThanOrEqualTo(2), reason: 'at $n points: ${diff.take(5)}');
        }
      });

      test('finishing a live stroke builds what a full build builds ($name @ $streamline)', () {
        final builder = LiveStrokeBuilder(spec);
        for (var n = 2; n <= points.length; n += 5) {
          builder.update(points.sublist(0, n));
        }
        // At pen-up: a lift flick, and the last pressures settled.
        final last = points.last;
        final done = [
          ...points.sublist(0, points.length - 2),
          for (final p in points.sublist(points.length - 2)) StrokePoint(p.x, p.y, 0.2),
          StrokePoint(last.x + 0.8, last.y + 1.2, 0.2),
          StrokePoint(last.x + 0.4, last.y + 2.4, 0.2),
        ];
        final diff = differences(builder.finish(done), StrokeOutline.build(done, spec));
        expect(diff.length, lessThanOrEqualTo(2), reason: '${diff.take(5)}');
      });
    }
  }
}
