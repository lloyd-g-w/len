@Tags(['perf'])
library;

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:len/ink/input/scribble_detector.dart';

/// Scribble to erase checks every pen move: its cost must stay flat with
/// the stroke's length (each look scans only the last
/// [ScribbleDetector.maxDuration]), or a very long stroke would lag.
void main() {
  /// Pen positions every 4 ms: cursive-like writing moving on along a line
  /// (no scribble), or a scribble going on and on (one zigzag).
  Offset writing(int i) => Offset(i * 3.0, 20 * math.sin(i / 4));
  Offset scribbling(int i) => Offset(40 * math.sin(i * math.pi / 6) + i * 0.02, i * 0.05);

  /// Microseconds per move over the last [tail] moves of a stroke [length]
  /// moves long, the end (pen-up: its zigzags) included.
  (double, int) perMove(int length, Offset Function(int) at, {int tail = 2000}) {
    final detector = ScribbleDetector()..begin(at(0), 0);
    for (var i = 1; i < length - tail; i++) {
      detector.add(at(i), i * 4);
    }
    final watch = Stopwatch()..start();
    for (var i = length - tail; i < length; i++) {
      detector.add(at(i), i * 4);
    }
    final zigzags = detector.windows.length;
    watch.stop();
    return (watch.elapsedMicroseconds / tail, zigzags);
  }

  for (final (name, at, zigzags) in [('writing', writing, 0), ('scribbling', scribbling, 1)]) {
    test('$name: a move costs the same on a stroke 16× as long', () {
      const short = 4000, long = 64000;
      var bestShort = double.infinity, bestLong = double.infinity;
      // Best of interleaved batches: a busy machine slows both alike.
      for (var round = 0; round < 5; round++) {
        final (s, found) = perMove(short, at);
        final (l, _) = perMove(long, at);
        expect(found, zigzags, reason: 'what the stroke is');
        bestShort = math.min(bestShort, s);
        bestLong = math.min(bestLong, l);
      }
      // ignore: avoid_print
      print(
        'scribble perf ($name): ${bestShort.toStringAsFixed(2)} µs/move at $short moves, '
        '${bestLong.toStringAsFixed(2)} µs/move at $long',
      );
      // Flat: generous room for noise, far below the 16× of a linear scan.
      expect(bestLong, lessThan(bestShort * 3 + 2));
    });
  }
}
