// The Ink Lab quality suite (inklab_test.dart) at stabiliser 1: a file
// of its own so the suite runs in parallel.
@Tags(['inklab'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'judge.dart';
import 'suite.dart';

void main() => judgeEntries(entriesAt(suiteEntries(), 1));
