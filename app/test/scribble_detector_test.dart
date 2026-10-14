import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/ink/input/scribble_detector.dart';
import 'package:len/ink/lab/raw_samples.dart';
import 'package:len/ink/lab/recording_codec.dart';

import 'inklab/sim/cases.dart';
import 'inklab/sim/pen_motion.dart';

/// Feeds [points] (with [times] in ms) to a detector as the pen would.
bool scribbles(List<Offset> points, List<int> times) {
  final d = ScribbleDetector()..begin(points.first, times.first);
  for (var i = 1; i < points.length; i++) {
    d.add(points[i], times[i]);
  }
  return d.isScribble;
}

/// [motion] sampled at a 240 Hz digitiser, scaled by [scale].
bool motionScribbles(PenMotion motion, {double scale = 1}) {
  final points = <Offset>[], times = <int>[];
  final origin = motion.at(0);
  for (var t = 0.0; t <= motion.duration; t += 1 / 240) {
    points.add(origin + (motion.at(t) - origin) * scale);
    times.add((t * 1000).round());
  }
  return points.length > 1 && scribbles(points, times);
}

/// A back-and-forth scribble: [passes] strokes [width] px long, drifting
/// [drift] px across per pass, [passMs] each, tilted by [angle].
PenMotion scribble({
  int passes = 8,
  double width = 80,
  double drift = 3,
  double passMs = 70,
  double angle = 0,
}) {
  final corners = [for (var i = 0; i <= passes; i++) Offset(i.isEven ? 0 : width, i * drift)];
  final c = math.cos(angle), s = math.sin(angle);
  return polyline([
    for (final p in corners)
      const Offset(300, 300) + Offset(p.dx * c - p.dy * s, p.dx * s + p.dy * c),
  ], segmentSeconds: passMs / 1000);
}

void main() {
  group('scribbles are recognised', () {
    test('horizontal, tilted, vertical, small and large', () {
      expect(motionScribbles(scribble()), isTrue);
      expect(motionScribbles(scribble(angle: 0.4)), isTrue);
      expect(motionScribbles(scribble(angle: math.pi / 2)), isTrue);
      expect(motionScribbles(scribble(width: 30, drift: 2, passMs: 50)), isTrue);
      expect(motionScribbles(scribble(width: 200, drift: 8, passMs: 110)), isTrue);
      expect(motionScribbles(scribble(passes: 6)), isTrue);
    });

    test('with round turns, as a hand moves (an oscillation)', () {
      for (final (width, drift, ms) in [(80.0, 3.0, 70.0), (40.0, 3.0, 60.0), (120.0, 8.0, 90.0)]) {
        const passes = 8;
        final omega = math.pi / (ms / 1000);
        final motion = PenMotion(
          duration: passes * ms / 1000,
          at: (t) => Offset(width / 2 * (1 - math.cos(omega * t)), drift * t * 1000 / ms),
          pressure: (_) => 0.5,
        );
        expect(motionScribbles(motion), isTrue, reason: '$width × $drift in $ms ms');
      }
    });

    test('two quick back-and-forths are enough', () {
      for (final (width, drift, ms) in [
        (80.0, 3.0, 70.0),
        (40.0, 3.0, 60.0),
        (30.0, 2.0, 50.0),
        (120.0, 6.0, 90.0),
        (200.0, 10.0, 120.0),
      ]) {
        for (final angle in [0.0, 0.5, math.pi / 2, 2.5]) {
          expect(
            motionScribbles(
              scribble(passes: 4, width: width, drift: drift, passMs: ms, angle: angle),
            ),
            isTrue,
            reason: '$width × $drift in $ms ms at $angle',
          );
        }
        // Round turns, as a hand oscillates.
        final omega = math.pi / (ms / 1000);
        final motion = PenMotion(
          duration: 4 * ms / 1000,
          at: (t) => Offset(width / 2 * (1 - math.cos(omega * t)), drift * t * 1000 / ms),
          pressure: (_) => 0.5,
        );
        expect(motionScribbles(motion), isTrue, reason: 'oscillating $width × $drift in $ms ms');
      }
    });

    test('but not too few passes, slow ones, tiny ones or ones moving on', () {
      expect(motionScribbles(scribble(passes: 3)), isFalse, reason: 'two reversals');
      expect(motionScribbles(scribble(passMs: 300)), isFalse, reason: 'slow');
      expect(motionScribbles(scribble(width: 10, drift: 1)), isFalse, reason: 'jitter-sized');
      expect(motionScribbles(scribble(width: 30, drift: 12)), isFalse, reason: 'a zigzag line');
    });
  });

  group('only the zigzag counts (R8-25, R8-32)', () {
    /// A detector fed [points], [stepMs] apart.
    ScribbleDetector fed(List<Offset> points, {int stepMs = 4}) {
      final d = ScribbleDetector()..begin(points.first, 0);
      for (var i = 1; i < points.length; i++) {
        d.add(points[i], i * stepMs);
      }
      return d;
    }

    List<Offset> line(Offset a, Offset b) {
      final n = ((b - a).distance / 4).ceil();
      return [for (var i = 1; i <= n; i++) Offset.lerp(a, b, i / n)!];
    }

    List<Offset> zigzag(double x0, double x1, double y, {int passes = 8}) => [
      for (var k = 0; k < passes; k++)
        ...line(Offset(k.isEven ? x0 : x1, y + k * 2), Offset(k.isEven ? x1 : x0, y + k * 2 + 2)),
    ];

    Rect bounds(List<Offset> path) => path
        .skip(1)
        .fold(
          Rect.fromPoints(path.first, path.first),
          (r, p) => r.expandToInclude(Rect.fromPoints(p, p)),
        );

    test('a lead-in along the axis and a run-on are cut off', () {
      final d = fed([
        ...line(const Offset(0, 100), const Offset(300, 100)),
        ...zigzag(300, 380, 100),
        ...line(const Offset(300, 116), const Offset(700, 116)),
      ]);
      expect(d.isScribble, isTrue);
      final b = bounds(d.paths.expand((p) => p).toList());
      expect(b.left, greaterThan(290));
      expect(b.right, lessThan(390));
    });

    test('a scribble stays found however long the stroke goes on', () {
      final d = fed([
        ...zigzag(100, 180, 100),
        // Five seconds of wandering on.
        for (var i = 0; i < 1250; i++) Offset(200 + i * 0.4, 100 + 20 * math.sin(i / 20)),
      ]);
      expect(d.isScribble, isTrue);
      expect(d.windows, hasLength(1));
      expect(bounds(d.paths.single).right, lessThan(190));
    });

    test('two scribbles in one stroke are two zigzags', () {
      final d = fed([
        ...zigzag(100, 180, 100),
        ...line(const Offset(100, 116), const Offset(400, 116)),
        ...zigzag(400, 480, 116),
      ]);
      expect(d.windows, hasLength(2));
    });
  });

  group('writing never scribbles', () {
    test('the simulated cases, at 1× to 4× (zoomed in)', () {
      for (final c in simCases) {
        for (final scale in [1.0, 2.0, 3.0, 4.0]) {
          for (final (k, contact) in c.contacts.indexed) {
            expect(
              motionScribbles(contact.motion, scale: scale),
              isFalse,
              reason: '${c.name} contact $k at $scale×',
            );
          }
        }
      }
    });

    test('cursive m, n, u and w sequences at many sizes and speeds', () {
      const narrow = (height: 1.0, loop: 0.2);
      for (final letters in [
        [for (var i = 0; i < 10; i++) letterU],
        [for (var i = 0; i < 10; i++) narrow],
        [
          for (var i = 0; i < 8; i++) ...[letterE, letterU],
        ],
      ]) {
        for (final xHeight in [10.0, 20.0, 30.0, 50.0]) {
          for (final width in [0.4, 0.7, 1.0]) {
            for (final speed in [3.0, 4.5, 7.0]) {
              final motion = cursive(
                const Offset(100, 200),
                letters,
                xHeight: xHeight,
                letterWidth: xHeight * width,
                lettersPerSecond: speed,
              );
              expect(
                motionScribbles(motion),
                isFalse,
                reason: 'x-height $xHeight, width ${xHeight * width}, $speed letters/s',
              );
            }
          }
        }
      }
    });

    test('printed zigzag letters and words (z, N, M, W, w, v, vvv, www, zz)', () {
      // Corners of each letter in a 1 × 1 box (y down), joined into words.
      const z = [Offset(0, 0), Offset(1, 0), Offset(0, 1), Offset(1, 1)];
      const n = [Offset(0, 1), Offset(0, 0), Offset(1, 1), Offset(1, 0)];
      const m = [Offset(0, 1), Offset(0, 0), Offset(0.5, 0.8), Offset(1, 0), Offset(1, 1)];
      const w = [Offset(0, 0), Offset(0.25, 1), Offset(0.5, 0.2), Offset(0.75, 1), Offset(1, 0)];
      const v = [Offset(0, 0), Offset(0.5, 1), Offset(1, 0)];
      List<Offset> word(List<Offset> letter, int count) => [
        for (var i = 0; i < count; i++)
          for (final (k, c) in letter.indexed)
            if (i == 0 || k > 0) Offset(c.dx + i * 1.1, c.dy),
      ];
      final words = {
        'z': word(z, 1),
        'zz': word(z, 2),
        'N': word(n, 1),
        'M': word(m, 1),
        'MM': word(m, 2),
        'w': word(w, 1),
        'www': word(w, 3),
        'vvv': word(v, 3),
      };
      for (final MapEntry(key: name, value: corners) in words.entries) {
        for (final height in [10.0, 20.0, 35.0, 60.0]) {
          for (final aspect in [0.5, 0.8, 1.2]) {
            for (final ms in [50.0, 80.0, 140.0]) {
              final motion = polyline([
                for (final c in corners)
                  const Offset(100, 200) + Offset(c.dx * height * aspect, c.dy * height),
              ], segmentSeconds: ms / 1000);
              expect(
                motionScribbles(motion),
                isFalse,
                reason: '$name, $height px tall, $aspect wide, $ms ms per stroke',
              );
            }
          }
        }
      }
    });

    test('zigzag hatching: shading spaced a tenth of its length or more', () {
      // Shading a shape or a letter with one back-and-forth stroke: lines
      // 12 to 120 px long, at least a tenth of that apart (from 3 px),
      // at any angle and pace. Denser hatching over ink is a scribble
      // (the strokes about to go dim first; the setting turns it off).
      for (final length in [12.0, 20.0, 30.0, 45.0, 60.0, 80.0, 120.0]) {
        for (final spacing in {math.max(3.0, length / 10), length / 6, length / 3}) {
          for (final passes in [6, 10, 16]) {
            for (final ms in [50.0, 90.0, 150.0]) {
              for (final angle in [0.0, 0.8, math.pi / 2, 2.3]) {
                final hatch = scribble(
                  passes: passes,
                  width: length,
                  drift: spacing,
                  passMs: ms,
                  angle: angle,
                );
                expect(
                  motionScribbles(hatch),
                  isFalse,
                  reason: '$passes lines $length px long, $spacing px apart, $ms ms, $angle',
                );
              }
            }
          }
        }
      }
    });

    test('cursive zigzags: m, w and z joined up, at many sizes and speeds', () {
      const arch = (height: 1.0, loop: 0.0), tall = (height: 1.4, loop: 0.3);
      for (final letters in [
        [arch, arch, arch, arch, arch, arch], // mm
        [letterU, letterU, letterU, letterU], // w-like cups
        [arch, tall, arch, tall, arch], // zigzag-ish cursive
      ]) {
        for (final xHeight in [10.0, 20.0, 35.0]) {
          for (final width in [0.5, 0.8]) {
            for (final speed in [3.0, 5.0, 8.0]) {
              final motion = cursive(
                const Offset(100, 200),
                letters,
                xHeight: xHeight,
                letterWidth: xHeight * width,
                lettersPerSecond: speed,
              );
              expect(motionScribbles(motion), isFalse, reason: '$xHeight $width $speed');
            }
          }
        }
      }
    });

    for (final file in Directory('test/inklab/recordings').listSync().whereType<File>()) {
      final name = file.uri.pathSegments.last;
      test('every contact of $name', () {
        final recording = RecordingCodec.decode(file.readAsBytesSync());
        final contacts = rawContacts(recording);
        expect(contacts, isNotEmpty);
        for (final (k, contact) in contacts.indexed) {
          final samples = contact.samples;
          if (samples.length < 2) continue;
          // At the zoom it was written at, and twice as large.
          for (final scale in [1.0, 2.0]) {
            final origin = samples.first.position;
            expect(
              scribbles(
                [for (final s in samples) origin + (s.position - origin) * scale],
                [for (final s in samples) s.timeUs ~/ 1000],
              ),
              isFalse,
              reason: '$name contact $k at $scale×',
            );
          }
        }
      });
    }
  });
}
