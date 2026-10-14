// `perf.flatness` judges that the live stroke costs O(1) per frame, not
// O(length): here it must pass on the real builder and fail on builders
// that do O(length) work every frame, measured the same way (fastest of
// several replays per frame, as `Subject.of(timed: true)`). Outlining the
// whole stroke every frame as well (what the capsule engine did) measures
// ≈ 7×, only re-shaping it ≈ 6×; the live builder ≈ 1.0×.
@Tags(['inklab'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/lab/input_recording.dart';
import 'package:len/ink/lab/replay_run.dart';
import 'package:len/ink/render/live_stroke.dart';
import 'package:len/ink/render/stroke_outline.dart';
import 'package:len/ink/render/stroke_renderer.dart';

import 'metrics/metric.dart';
import 'metrics/performance_metrics.dart';
import 'sim/cases.dart';

Metric _flatness(InputRecording r, {LiveOutline Function(LiveInk)? build}) =>
    performance(ReplayResult.run(r, timingRepeats: 3, buildLive: build))
        .firstWhere((m) => m.id == 'perf.flatness');

void main() {
  final recording = simCases
      .firstWhere((c) => c.name == 'long_stroke')
      .record(defaultPen)
      .recording;

  test('the live builder is flat', () {
    final m = _flatness(recording);
    expect(m.pass, isTrue, reason: '$m ${m.note}');
  });

  test('a builder that also outlines the whole stroke every frame is not', () {
    final m = _flatness(
      recording,
      build: (live) {
        StrokeOutline.build(
          live.points,
          StrokeRenderer.specFor(live.width, live.style),
          complete: false,
        );
        return LiveStrokeBuilder.livePath(live);
      },
    );
    expect(m.pass, isFalse, reason: '$m ${m.note}');
  });
}
