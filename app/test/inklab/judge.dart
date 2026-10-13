import 'package:flutter_test/flutter_test.dart';

import 'known_failures.dart';
import 'suite.dart';

/// One group per entry with one test per metric, held to the metric's
/// limit; metrics in `known_failures.dart` are skipped with their finding.
void judgeEntries(Iterable<SuiteEntry> entries) {
  for (final entry in entries) {
    group(entry.name, () {
      for (final id in metricIds) {
        // Timing metrics are only meaningful on long, timed contacts.
        if (id.startsWith('perf.') && !entry.judgedTiming) continue;
        final known = knownFailure(id, entry.caseName, entry.streamline);
        test(id, () {
          final m = entry.metric(id);
          if (m == null) return; // Not applicable (no cusps, taps, …).
          expect(m.pass, isTrue, reason: '$m at ${m.where} ${m.note}');
        }, skip: known == null ? false : '${known.finding}: ${known.why}');
      }
    });
  }
}
