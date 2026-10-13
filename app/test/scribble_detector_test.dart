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

    test('but not too few passes, slow ones, tiny ones or ones moving on', () {
      expect(motionScribbles(scribble(passes: 4)), isFalse, reason: 'three reversals');
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
