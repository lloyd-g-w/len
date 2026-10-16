@Tags(['perf'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/big_library.dart';
import 'support/startup_library.dart';

/// Writes the library launches are measured on (see docs/PERFORMANCE.md,
/// "Startup") into the app data folder `$LEN_STARTUP_LIBRARY` (e.g.
/// `$XDG_DATA_HOME/dev.len.len`): 300 notebooks, a 500-page notebook of
/// handwriting with recordings, the workspace left in it. Skipped unless
/// that variable is set.
void main() {
  final out = Platform.environment['LEN_STARTUP_LIBRARY'];
  test(
    'write the startup library',
    () {
      final dir = Directory(out!)..createSync(recursive: true);
      final path = '${dir.path}/len.db';
      if (File(path).existsSync()) fail('$path exists');
      final clock = BenchClock();
      final s = openServices(path, clock);
      final made = StartupLibrary.build(s, clock);
      StartupLibrary.writeMarker(s, path);
      s.database.db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      final strokes = s.database.db.select('SELECT COUNT(*) AS n FROM strokes').first['n'];
      s.dispose();
      report(
        'wrote $path: ${made.library.notebooks.length + 1} notebooks, $strokes strokes, '
        '${File(path).lengthSync() >> 20} MB',
      );
    },
    skip: out == null ? 'set LEN_STARTUP_LIBRARY' : false,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
