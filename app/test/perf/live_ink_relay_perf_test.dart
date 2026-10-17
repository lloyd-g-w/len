@Tags(['perf'])
library;

import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/live_ink/live_ink_relay.dart';
import 'package:len/ink/input/ink_events.dart';
import 'package:len/ink/input/live_ink.dart';

/// What relaying the stroke being written (live ink) costs the local pen:
/// a point added to `LiveInk` with the relay listening (someone in the
/// room: messages encoded every 50 ms) against no relay. Best of
/// interleaved batches, on fake time (a 240 Hz pen).
void main() {
  test('live ink relay: per-point cost on the local pen', () {
    const strokes = 40;
    const points = 600; // 2.5 s at 240 Hz.
    var bytes = 0;

    /// Microseconds to write [strokes] strokes, with or without a relay.
    int run({required bool relay}) {
      var micros = 0;
      fakeAsync((async) {
        final live = LiveInk();
        final events = InkEvents();
        final r = relay
            ? LiveInkRelay(
                live: live,
                events: events,
                send: (data) => bytes += jsonEncode(data).length,
                anyoneThere: () => true,
              )
            : null;
        final watch = Stopwatch();
        for (var s = 0; s < strokes; s++) {
          live.begin(tool: InkTool.ballpoint, color: 0xFF000000, width: 2);
          watch.start();
          live.add(const StrokePoint(0, 0, 0.5));
          events.inkBegan?.call('page');
          watch.stop();
          for (var i = 1; i < points; i++) {
            watch.start();
            live.add(StrokePoint(i * 0.7, i * 0.3, 0.5));
            watch.stop();
            async.elapse(const Duration(microseconds: 4167));
          }
          watch.start();
          live.finish();
          events.inkEnded?.call('s$s');
          watch.stop();
        }
        micros = watch.elapsedMicroseconds;
        r?.dispose();
      });
      return micros;
    }

    var bare = 1 << 62;
    var relayed = 1 << 62;
    for (var batch = 0; batch < 7; batch++) {
      final b = run(relay: false);
      if (b < bare) bare = b;
      final r = run(relay: true);
      if (r < relayed) relayed = r;
    }
    final perPoint = (relayed - bare) / (strokes * points);
    // ignore: avoid_print
    print(
      'live ink relay: ${(bare / (strokes * points)).toStringAsFixed(2)} µs/point bare, '
      '${(relayed / (strokes * points)).toStringAsFixed(2)} µs/point relayed '
      '(+${perPoint.toStringAsFixed(2)} µs), ${bytes ~/ (7 * strokes)} bytes sent per stroke',
    );
    // Generous: a busy machine. A pen point every 4 ms leaves the relay
    // far below a percent of it.
    expect(perPoint, lessThan(20));
  });
}
