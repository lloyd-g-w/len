// Prints every metric of every suite entry as a table (opt-in, for working
// on the engine):
//
//   flutter test test/inklab/tools/table_test.dart --dart-define=INKLAB_TABLE=true \
//     [--dart-define=INKLAB_ONLY=<regex on entry names>]
@Tags(['inklab'])
library;

import 'package:flutter_test/flutter_test.dart';

import '../suite.dart';

const bool _enabled = bool.fromEnvironment('INKLAB_TABLE');
const String _only = String.fromEnvironment('INKLAB_ONLY');

void main() {
  test(
    'metric table',
    () {
      final filter = RegExp(_only);
      var fails = 0;
      for (final e in suiteEntries()) {
        if (!filter.hasMatch(e.name)) continue;
        final cells = <String>[];
        // Every metric, also the ones reported without a limit (overlay at
        // other pipeline depths).
        for (final m in e.metrics) {
          final id = m.id;
          if (id.startsWith('perf.') &&
              e.caseName != 'long_stroke' &&
              !e.caseName.startsWith('rec:')) {
            continue;
          }
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
