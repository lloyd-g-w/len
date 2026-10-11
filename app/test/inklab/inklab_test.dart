// The Ink Lab quality suite: every metric on every simulated case (at
// stabiliser 0, 0.4 and 1) and every recording in test/inklab/recordings/.
// Metrics that fail on the current pen engine are skipped with the finding
// that explains them (docs/INK_LAB.md, "Findings"); the visual report
// (report/report_test.dart) still shows them.
@Tags(['inklab'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'known_failures.dart';
import 'suite.dart';

void main() {
  for (final entry in suiteEntries()) {
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
