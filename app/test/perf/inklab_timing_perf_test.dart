// The Ink Lab's timing metrics (docs/INK_LAB.md) on every timed entry,
// held to their limits however busy the machine: the default tier's suite
// relaxes the absolute ones on a busy machine (`judge.dart`).
@Tags(['perf'])
library;

import 'package:flutter_test/flutter_test.dart';

import '../inklab/judge.dart';
import '../inklab/suite.dart';

void main() => judgeEntries(
  suiteEntries().where((e) => e.judgedTiming),
  strictTiming: true,
  only: (id) => id.startsWith('perf.'),
);
