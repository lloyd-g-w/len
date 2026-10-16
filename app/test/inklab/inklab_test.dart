// The Ink Lab quality suite: every metric on every simulated case (at
// stabiliser 0, 0.4 and 1) and every recording in test/inklab/recordings/.
// Metrics that fail on the current pen engine are skipped with the finding
// that explains them (docs/INK_LAB.md, "Findings"); the visual report
// (report/report_test.dart) still shows them. Flat pen ends:
// flat_ends_suite_test.dart. This file judges the entries at stabiliser 0
// (and recordings at their own); those at 0.4 and 1 are in
// inklab_stabiliser_0_4_test.dart and inklab_stabiliser_1_test.dart.
@Tags(['inklab'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'judge.dart';
import 'suite.dart';

void main() => judgeEntries(entriesAt(suiteEntries(), null));
