// The on-device flicker log (`FlickerLog`, docs/INK_LAB.md "Flicker log"):
// it must name a hand-over gap when the overlay let go of a frame's ink
// before Flutter could show that frame, stay quiet otherwise, and measure
// how far the overlay's ink of a stroke reaches outside Flutter's.
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/ink/input/wet_ink.dart';
import 'package:len/ink/lab/flicker_geometry.dart';
import 'package:len/ink/lab/flicker_log.dart';
import 'package:len/ink/lab/raw_samples.dart';
import 'package:len/ink/lab/replay_run.dart';
import 'package:len/ink/lab/wet_ink_model.dart';
import 'package:len/ink/render/stroke_renderer.dart';

import 'inklab/metrics/temporal_metrics.dart';
import 'inklab/sim/cases.dart';

FrameTiming _timing(int buildStart, int buildFinish, int rasterFinish) => FrameTiming(
  vsyncStart: buildStart,
  buildStart: buildStart,
  buildFinish: buildFinish,
  rasterStart: buildFinish,
  rasterFinish: rasterFinish,
  rasterFinishWallTime: rasterFinish,
);

void main() {
  group('hand-over timing', () {
    test('a frame let go of before it could be on screen is a gap', () {
      final log = FlickerLog(enabled: true);
      // Built 0–3 ms, reported at 3.2 ms, rasterised only at 120 ms.
      log
        ..frameReported(1, 3200)
        ..frameTimings([_timing(0, 3000, 120000)])
        ..frameReleased(1, 73200);
      expect(log.entries.single.kind, 'gap');
      expect(log.entries.single.detail, contains('ink missing'));
    });

    test('a frame let go of after it is on screen is fine, in either order', () {
      final log = FlickerLog(enabled: true)
        ..frameReported(1, 3200)
        ..frameReleased(1, 73200)
        ..frameReported(2, 11500)
        ..frameTimings([_timing(0, 3000, 9000), _timing(8300, 11300, 18000)])
        ..frameReleased(2, 81500);
      expect(log.entries, isEmpty);
      expect(log.frames, 2);
    });

    test('the committed stroke\'s frame is named as such', () {
      final log = FlickerLog(enabled: true)
        ..frameReported(5, 3200)
        ..frameEnded(5)
        ..frameReleased(5, 50000, end: true)
        ..frameTimings([_timing(0, 3000, 60000)]);
      expect(log.entries.single.kind, 'end');
      expect(log.strokes, 1);
    });

    test('nothing is kept while off', () {
      final log = FlickerLog(enabled: false)
        ..frameReported(1, 3200)
        ..frameTimings([_timing(0, 3000, 120000)])
        ..frameReleased(1, 73200)
        ..retract(4, 0)
        ..geometry(3, Offset.zero, 0);
      expect(log.entries, isEmpty);
    });

    test('small retracts only count', () {
      final log = FlickerLog(enabled: true)
        ..retract(0.3, 0)
        ..retract(1.5, 10);
      expect(log.entries.single.kind, 'retract');
      expect(log.worstRetractPx, 1.5);
    });
  });

  group('geometry at hand-over', () {
    // The overlay model's ink of each contact against Flutter's committed
    // stroke, in physical px as the overlay draws.
    double worstExcess(String name, {double inflate = 1}) {
      final c = simCases.firstWhere((c) => c.name == name);
      final r = ReplayResult.run(c.record(defaultPen).recording);
      final dpr = r.recording.meta.devicePixelRatio;
      final contacts = rawContacts(r.recording);
      var worst = 0.0;
      for (final run in contactRuns(r)) {
        final stroke = run.committed;
        if (stroke == null) continue;
        final view = run.frames.first;
        final toPx = physical(r, view);
        final o = toPx(Offset.zero), x = toPx(const Offset(1, 0)) - o;
        final path = StrokeRenderer.pathOf(stroke).transform(
          Float64List.fromList([x.dx, 0, 0, 0, 0, x.dx, 0, 0, 0, 0, 1, 0, o.dx, o.dy, 0, 1]),
        );
        final wet = WetInkStyle.forPen(
          r.pen.tool,
          r.pen.width,
          stroke.style,
          color: 0xFF000000,
          scale: view.viewScale,
          stabiliser: view.stabiliser,
        )!;
        final first = view.toScreen(view.points.first.x, view.points.first.y);
        final contact = contacts.firstWhere((c) => (c.samples.first.position - first).distance < 1);
        final model = WetInkModel(
          radii: [for (final x in wet.radii) x * dpr * inflate],
          shape: wet.shape.scaled(dpr),
          frameMs: 8.3,
        );
        for (final (i, s) in contact.samples.indexed) {
          model.add(
            s.position * dpr,
            s.pressure,
            s.timeUs ~/ 1000,
            lift: i == contact.samples.length - 1,
          );
        }
        model.commit(taperEnd: StrokeRenderer.specFor(r.pen.width, stroke.style).taperEnd * x.dx);
        final (excess, _) = overlayExcess(model.segments(0, model.samples.length), path.contains);
        if (excess > worst) worst = excess;
      }
      return worst;
    }

    for (final name in ['cursive', 'hooks', 'fast_loops']) {
      test('$name: the overlay draws inside Flutter\'s committed ink', () {
        expect(worstExcess(name), 0);
      });
    }

    test('a wider overlay shows', () {
      expect(worstExcess('cursive', inflate: 1.5), greaterThan(0.5));
    });
  });
}
