import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/render/live_stroke.dart';
import 'package:len/ink/render/stroke_outline.dart';
import 'package:len/ink/render/stroke_shaper.dart';

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

  for (final (streamline, unit) in [(0.0, 0.0), (0.4, 0.0), (1.0, 0.0), (0.0, 1.0), (0.4, 1.0)]) {
    final spec = OutlineSpec(width: 2.5, thinning: 0.25, streamline: streamline, unit: unit);
    for (final MapEntry(key: name, value: points) in strokes.entries) {
      final name_ = unit > 0 ? '$name, unit $unit' : name;
      test('the live builder draws what a full rebuild draws ($name_ @ $streamline)', () {
        final builder = LiveStrokeBuilder(spec);
        for (var n = 2; n <= points.length; n += 7) {
          final prefix = points.sublist(0, n);
          final live = builder.update(prefix).combined;
          final full = StrokeOutline.build(prefix, spec, complete: false);
          final diff = differences(live, full);
          expect(diff.length, lessThanOrEqualTo(2), reason: 'at $n points: ${diff.take(5)}');
        }
      });

      test('finishing a live stroke builds what a full build builds ($name_ @ $streamline)', () {
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

  group('from pen-down', () {
    const spec = OutlineSpec(width: 2.5, thinning: 0.25, streamline: 0.4, unit: 1);
    // A flick landing on a stroke to the right (hooks_test.dart's landing).
    final hooked = [
      for (var i = 3; i > 0; i--) StrokePoint(-1.2 * i / 3, 2.2 * i / 3, 0.5),
      for (var i = 0; i < 40; i++) StrokePoint(i * 0.9, 0, 0.5),
    ];
    final straight = [for (var i = 0; i < 40; i++) StrokePoint(i * 0.9, 0, 0.5)];

    test('ink covers where the pen landed from the first point on', () {
      final builder = LiveStrokeBuilder(spec);
      for (var n = 1; n <= straight.length; n++) {
        final path = builder.update(straight.sublist(0, n)).combined;
        expect(path.contains(straight.first.offset), isTrue, reason: 'at $n points');
      }
    });

    test('a pen-down hook is trimmed once, a few px after landing; the rest never changes', () {
      // Stabiliser off: the live line reaches the pen.
      final builder = LiveStrokeBuilder(
        const OutlineSpec(width: 2.5, thinning: 0.25, streamline: 0, unit: 1),
      );
      Path? previous;
      var changes = 0;
      int? trimmedAt;
      for (var n = 1; n <= hooked.length; n++) {
        final path = builder.update(hooked.sublist(0, n)).combined;
        final landed = path.contains(hooked.first.offset);
        if (!landed) trimmedAt ??= n;
        expect(landed, trimmedAt == null, reason: 'at $n points');
        if (previous != null) {
          // Changes behind the tip (beyond the newest points' reach).
          final tip = hooked[n - 2].offset;
          final behind = differences(
            previous,
            path,
          ).where((p) => (p - tip).distance > 3.5).toList();
          if (behind.isNotEmpty) {
            changes++;
            // Only within the hook (≤ 3 px) and the pen's radius around it.
            for (final p in behind) {
              expect(p.dx, lessThan(1.5), reason: 'at $n points: $p');
            }
          }
        }
        previous = path;
      }
      expect(changes, 1);
      // Decided within about 5 px of travel.
      expect(trimmedAt, inInclusiveRange(4, 9));
    });
  });

  group('with the stabiliser on', () {
    final points = Handwriting(seed: 3).cursive(const Offset(0, 30), [e, l, u, e]);
    for (final streamline in [0.4, 1.0]) {
      final spec = OutlineSpec(width: 2.5, thinning: 0.25, streamline: streamline, unit: 1);
      test('live ink only grows, trailing the pen by the smoothing\'s reach (@ $streamline)', () {
        final builder = LiveStrokeBuilder(spec);
        final params = spec.paramsFor(1);
        final reach = (params.kernelK + params.cornerK + params.lag + 8) * params.step;
        Path? previous;
        for (var n = 1; n <= points.length; n += 3) {
          final path = builder.update(points.sublist(0, n)).combined;
          expect(path.contains(points.first.offset), isTrue, reason: 'at $n points');
          if (previous != null) {
            // Lost ink, beyond an edge's refit (a grid point right on an
            // edge may flip as the tail's curves are refitted).
            bool near(Offset p) => [
              for (final d in const [
                Offset(0.03, 0),
                Offset(-0.03, 0),
                Offset(0, 0.03),
                Offset(0, -0.03),
              ])
                p + d,
            ].any(path.contains);
            final lost = differences(
              previous,
              path,
            ).where((p) => previous!.contains(p) && !near(p));
            expect(lost, isEmpty, reason: 'ink taken back at $n points');
          }
          // Trailing the pen by no more than the smoothing needs.
          final shaper = StrokeOutline.feed(StrokeShaper(params), points.sublist(0, n), spec)
            ..update();
          if (shaper.started && shaper.length > 1) {
            final behind = shaper.length - shaper.liveLength;
            expect(behind * params.step, lessThanOrEqualTo(reach), reason: 'at $n');
            if (n > 40) expect(behind, greaterThan(params.kernelK), reason: 'at $n');
          }
          previous = path;
        }
      });
    }
  });
}
