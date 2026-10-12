import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/pen/pen_config.dart';
import 'package:len/ink/render/live_stroke.dart';
import 'package:len/ink/render/stroke_outline.dart';
import 'package:len/ink/render/stroke_renderer.dart';
import 'package:len/ink/render/taper.dart';

import 'live_stroke_test.dart' show differences;
import 'support/handwriting.dart';

/// Whether [path] covers a point within a hair of [p] (a grid point right
/// on an edge may flip as the tail's curves are refitted).
bool near(Path path, Offset p) => [
  for (final d in const [Offset(0.03, 0), Offset(-0.03, 0), Offset(0, 0.03), Offset(0, -0.03)])
    p + d,
].any(path.contains);

void main() {
  final hw = Handwriting(seed: 7);
  final strokes = {
    'cursive': hw.cursive(const Offset(0, 30), [e, l, l, e, u, e]),
    'line': [for (var i = 0; i <= 200; i++) StrokePoint(i * 0.7, 0.05 * math.sin(i * 1.3), 0.5)],
    'short': [for (var i = 0; i <= 12; i++) StrokePoint(i * 0.6, 0, 0.5)],
  };
  OutlineSpec spec(double streamline, {bool flat = false, double ts = 0, double te = 0}) =>
      OutlineSpec(
        width: 2.5,
        thinning: 0.25,
        streamline: streamline,
        unit: 1,
        flatCaps: flat,
        taperStart: ts,
        taperEnd: te,
      );

  group('style', () {
    test('ends round-trip through JSON and are parsed strictly', () {
      const tapered = StrokeStyle(ends: StrokeEnds.tapered, taperStart: 4, taperEnd: 2.5);
      expect(StrokeStyle.fromJson(tapered.toJson()), tapered);
      const flat = StrokeStyle(ends: StrokeEnds.flat);
      expect(StrokeStyle.fromJson(flat.toJson()), flat);
      expect(flat.toJson().containsKey('ts'), isFalse);
      for (final bad in [
        {'o': 1, 'th': 0.5, 'sl': 0}, // no ends
        {'o': 1, 'th': 0.5, 'sl': 0, 'e': 'pointy'},
        {'o': 1, 'th': 0.5, 'sl': 0, 'e': 'taper', 'ts': 2}, // no te
        {'o': 1, 'th': 0.5, 'sl': 0, 'e': 'round', 'ts': 2, 'te': 2},
        {'o': 1, 'th': 0.5, 'sl': 0, 'e': 'taper', 'ts': 99, 'te': 2},
      ]) {
        expect(() => StrokeStyle.fromJson(bad), throwsFormatException, reason: '$bad');
      }
    });

    test('a pen config gives its strokes its ends; the highlighter keeps flat ones', () {
      final config = PenConfig.defaultsFor(InkTool.ballpoint).copyWith(
        ends: const PenEnds(style: StrokeEnds.tapered, taperLength: 5, taperAt: TaperAt.end),
      );
      final style = config.styleFor(InkTool.ballpoint);
      expect((style.ends, style.taperStart, style.taperEnd), (StrokeEnds.tapered, 0.0, 5.0));
      final spec = StrokeRenderer.specFor(InkTool.ballpoint, 2, style);
      expect((spec.taperStart, spec.taperEnd, spec.flatCaps), (0.0, 10.0, false));
      final hl = StrokeRenderer.specFor(InkTool.highlighter, 10, style);
      expect((hl.taperEnd, hl.flatCaps), (0.0, true));
      expect(PenConfig.fromJson(config.toJson(), tool: InkTool.ballpoint), config);
    });

    test('the end taper follows the lift speed', () {
      expect(Taper.speedScale(0), Taper.minSpeedScale);
      expect(Taper.speedScale(Taper.referenceSpeed), closeTo(1, 1e-12));
      expect(Taper.speedScale(100), Taper.maxSpeedScale);
      // 1 px per ms over the last 20 ms.
      final speed = Taper.liftSpeed((i) => i * 2.0, (i) => 0, (i) => i * 2, 40);
      expect(speed, closeTo(1, 1e-12));
    });
  });

  for (final streamline in [0.0, 0.4]) {
    final variants = {
      'flat': spec(streamline, flat: true),
      'taper start': spec(streamline, ts: 10),
      'taper end': spec(streamline, te: 10),
      'taper both': spec(streamline, ts: 8, te: 12),
    };
    for (final MapEntry(key: style, value: s) in variants.entries) {
      for (final MapEntry(key: name, value: points) in strokes.entries) {
        // The cursive is slow to compare: once per stabiliser.
        if (name == 'cursive' && style != 'taper both') continue;
        test('live draws what a rebuild draws, and commits what a build builds '
            '($name, $style @ $streamline)', () {
          final builder = LiveStrokeBuilder(s);
          for (var n = 2; n <= points.length; n += 17) {
            final prefix = points.sublist(0, n);
            final live = builder.update(prefix).combined;
            final full = StrokeOutline.build(prefix, s, complete: false);
            expect(differences(live, full).length, lessThanOrEqualTo(2), reason: 'at $n');
          }
          // The end taper may be resolved at pen-up (following the speed).
          final committed = s.withTaperEnd(s.taperEnd * 0.7);
          final diff = differences(
            builder.finish(points, taperEnd: committed.taperEnd),
            StrokeOutline.build(points, committed),
          );
          expect(diff.length, lessThanOrEqualTo(2), reason: '${diff.take(5)}');
        });
      }
    }

    test('a start taper is drawn from pen-down and never changes (@ $streamline)', () {
      final s = spec(streamline, ts: 10);
      final points = strokes['line']!;
      final builder = LiveStrokeBuilder(s);
      Path? previous;
      // The taper's 10 units and well beyond.
      for (var n = 2; n <= 50; n++) {
        final path = builder.update(points.sublist(0, n)).combined;
        if (previous != null) {
          // Stabiliser off: nothing changes behind the tip; on: live ink
          // shows only the final line, so it only grows.
          final tip = points[n - 2].offset;
          final changed = differences(previous, path).where(
            (p) => streamline == 0
                ? (p - tip).distance > 3.5
                : previous!.contains(p) && !near(path, p),
          );
          expect(changed, isEmpty, reason: 'at $n');
        }
        previous = path;
      }
      final line = StrokeOutline.centerline(points, s)!;
      expect(line.r.first, lessThan(0.1));
      final body = line.r[line.r.length ~/ 2];
      final at = (5 / line.step).round(); // half way along the taper: 3/4 width
      expect(line.r[at] / body, closeTo(0.75, 0.05));
    });
  }

  test('tapered ends narrow to a point; round and flat ends keep their width', () {
    final points = strokes['line']!;
    double endRadius(OutlineSpec s) => StrokeOutline.centerline(points, s)!.r.last;
    final round = endRadius(spec(0));
    expect(round, greaterThan(1));
    expect(endRadius(spec(0, flat: true)), round);
    expect(endRadius(spec(0, te: 10)), lessThan(0.05 * round));
    // Live ink cannot know the end: it is round until pen-up.
    final live = StrokeOutline.centerline(points, spec(0, te: 10), complete: false)!;
    expect(live.r.last, round);
  });

  test('a flat end stops square at the end; a round one reaches a radius beyond', () {
    final points = strokes['line']!;
    final end = points.last.offset;
    final round = StrokeOutline.build(points, spec(0));
    final flat = StrokeOutline.build(points, spec(0, flat: true));
    for (final dy in [-0.8, 0.0, 0.8]) {
      expect(round.contains(end + Offset(0.6, dy)), isTrue);
      expect(flat.contains(end + Offset(0.6, dy)), isFalse);
      expect(flat.contains(end + Offset(-0.3, dy)), isTrue, reason: 'full width up to the end');
    }
    final start = points.first.offset;
    expect(flat.contains(start + const Offset(-0.6, 0)), isFalse);
    expect(round.contains(start + const Offset(-0.6, 0)), isTrue);
  });

  test('a tap is a dot whatever the ends', () {
    final tap = [for (var i = 0; i < 4; i++) StrokePoint(0.05 * i, 0, 0.5)];
    for (final s in [spec(0, ts: 10, te: 10), spec(0)]) {
      final path = StrokeOutline.build(tap, s);
      expect(path.contains(const Offset(0, 1.0)), isTrue);
    }
  });
}
