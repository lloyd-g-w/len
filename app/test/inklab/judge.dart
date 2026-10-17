import 'package:flutter_test/flutter_test.dart';

import 'known_failures.dart';
import 'suite.dart';

/// Timing metrics with absolute limits: this machine's microseconds, which
/// on a busy machine are the scheduler's as much as the code's. Ratios
/// (`perf.flatness`) and counts are judged as they are.
const Set<String> absoluteTimings = {'perf.frameCost', 'perf.commit'};

/// How far [absoluteTimings] are relaxed on a busy machine ([Subject.busy]):
/// enough for a full default tier beside other work (alone ≤ 4 ms of the
/// 8 ms `perf.commit` limit; a loaded run measured 9.5), not for a blow-up.
const double busyTimingFactor = 3;

/// One group per entry with one test per metric (of those [only] accepts),
/// held to the metric's limit; metrics in `known_failures.dart` are skipped
/// with their finding. [absoluteTimings] measured on a busy machine are
/// held to [busyTimingFactor] × their limit, unless [strictTiming] (the slow
/// tier's `test/perf/inklab_timing_perf_test.dart`).
void judgeEntries(
  Iterable<SuiteEntry> entries, {
  bool strictTiming = false,
  bool Function(String id)? only,
}) {
  for (final entry in entries) {
    group(entry.name, () {
      for (final id in metricIds.where(only ?? (_) => true)) {
        // Timing metrics are only meaningful on long, timed contacts.
        if (id.startsWith('perf.') && !entry.judgedTiming) continue;
        final known = knownFailure(id, entry.caseName, entry.streamline);
        test(id, () {
          var m = entry.metric(id);
          if (m == null) return; // Not applicable (no cusps, taps, …).
          if (!strictTiming && absoluteTimings.contains(id) && entry.subject.busy) {
            m = m.relaxed(busyTimingFactor, 'busy machine');
          }
          expect(m.pass, isTrue, reason: '$m at ${m.where} ${m.note}');
        }, skip: known == null ? false : '${known.finding}: ${known.why}');
      }
    });
  }
}
