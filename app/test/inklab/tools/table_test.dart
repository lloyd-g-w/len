// Prints every metric of every suite entry as a table (opt-in, for working
// on the engine):
//
//   flutter test test/inklab/tools/table_test.dart --dart-define=INKLAB_TABLE=true \
//     [--dart-define=INKLAB_ONLY=<regex on entry names>] \
//     [--dart-define=INKLAB_ENDS=both|flat|round|tapered]
//
// INKLAB_ENDS writes every entry with those pen ends (`cursive@0.4/flat`);
// `both` runs the table with the pen's round ends, then with flat ends
// (butt caps: the overlay's flat-end rules, `WetInkEnds`).
@Tags(['inklab'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/pen/pen_ends.dart';

import '../suite.dart';

const bool _enabled = bool.fromEnvironment('INKLAB_TABLE');
const String _only = String.fromEnvironment('INKLAB_ONLY');
const String _ends = String.fromEnvironment('INKLAB_ENDS');

void main() {
  test(
    'metric table',
    () {
      final filter = RegExp(_only);
      var fails = 0;
      final entries = _ends == 'both'
          ? [...suiteEntries(), ...suiteEntries(ends: const PenEnds(style: StrokeEnds.flat))]
          : suiteEntries(ends: suiteEnds());
      for (final e in entries) {
        if (!filter.hasMatch(e.name)) continue;
        final cells = <String>[];
        // Every judged metric, also the ones reported without a limit
        // (overlay at other pipeline depths).
        for (final m in e.judged) {
          final id = m.id;
          if (!m.pass) fails++;
          cells.add(
            '${m.pass ? '' : '!!'}$id=${m.formatted.split(' (').first}'
            '${m.pass || m.where == null ? '' : '@(${m.where!.dx.toStringAsFixed(1)},${m.where!.dy.toStringAsFixed(1)})'}',
          );
        }
        // ignore: avoid_print
        print('${e.name.padRight(22)} ${cells.join('  ')}');
      }
      // ignore: avoid_print
      print('FAILS: $fails');
    },
    skip: _enabled ? false : 'opt-in: --dart-define=INKLAB_TABLE=true',
    timeout: Timeout.none,
  );
}
