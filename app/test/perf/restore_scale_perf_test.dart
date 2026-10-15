import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/archive/len_scope.dart';
import 'package:len/data/blob_backend.dart';

import 'support/big_library.dart';

/// Restoring a big backup (200 notebooks, 10 pages each, ~9,000 long
/// strokes; several records parts): how long it takes and how long it holds
/// the UI thread at once. Records are parsed and written in slices
/// (`LenArchiveReader.sliceBudget`), so no turn holds a whole part.
void main() {
  test('restore a big library backup', () async {
    final clock = BenchClock();
    final source = AppServices.create(
      AppDatabase.inMemory(),
      blobBackend: MemoryBlobBackend(),
      clock: clock,
    );
    addTearDown(source.dispose);
    BigLibrary.build(source, clock, notebookCount: 200, trashCount: 0, coverLines: 25);
    final out = OutputMemoryStream();
    await source.lenFiles.write(const LenScope.library(), out);
    final bytes = out.getBytes();
    final parts = ZipDecoder()
        .decodeBytes(bytes)
        .files
        .where((f) => f.name.startsWith('records/'))
        .length;
    final strokes = source.database.db.select('SELECT COUNT(*) AS n FROM strokes').first['n'];

    final target = AppServices.create(AppDatabase.inMemory(), blobBackend: MemoryBlobBackend());
    addTearDown(target.dispose);
    final clockMs = Stopwatch()..start();
    var done = false;
    final restore = target.lenFiles
        .open(InputMemoryStream(bytes))
        .then((file) => target.lenFiles.import(file, folderName: 'Backup', keepIds: true))
        .whenComplete(() => done = true);
    final turns = await turnsUntil(() => done);
    final result = await restore;
    final total = clockMs.elapsedMilliseconds;
    turns.sort();
    final longest = turns.last;
    final p99 = turns[(turns.length * 0.99).floor().clamp(0, turns.length - 1)];
    report(
      'restore: ${bytes.length >> 20} MB, $parts records parts, $strokes strokes: $total ms; '
      '${turns.length} turns, p99 $p99 ms, longest $longest ms',
    );
    expect(result.notebooks, hasLength(200));
    // No turn holds a records part (before slicing: 13 turns, the longest
    // 516 ms of 3.2 s, every part one long turn). What remains longest is
    // the final transaction that adds the notebooks and marks everything
    // for sync (~160 ms here). The second longest is checked, so one GC
    // pause on a busy machine does not fail it; unsliced parts still would.
    final second = turns[turns.length - 2];
    expect(second * 10, lessThan(total), reason: 'longest $longest ms, second $second ms');
  });
}
