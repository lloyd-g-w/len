// The low-latency overlay with flat ends (`WetInkEnds`): on every simulated
// case at the default stabiliser, written with a flat-ended pen, the
// overlay's model must cover what Flutter's ink will be (no gap) and draw
// nothing round past the flat ends that Flutter's ink does not (ghost ink,
// as `overlay.ghost` judges it for round ends).
@Tags(['inklab'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/lab/replay_run.dart';
import 'package:len/ink/pen/pen_ends.dart';

import 'metrics/overlay_metrics.dart';
import 'sim/cases.dart';

void main() {
  for (final c in simCases) {
    test('flat ends: the overlay draws what Flutter will (${c.name})', () {
      final r = ReplayResult.run(
        c.record(defaultPen).recording,
        ends: const PenEnds(style: StrokeEnds.flat),
      );
      expect(r.style.ends, StrokeEnds.flat);
      final m = {for (final x in overlay(r)) x.id: x};
      expect(m['overlay.gap']!.value, 0, reason: '${m['overlay.gap']!.where}');
      expect(
        m['overlay.ghost']!.value,
        lessThanOrEqualTo(2),
        reason: '${m['overlay.ghost']!.where}',
      );
    });
  }
}
