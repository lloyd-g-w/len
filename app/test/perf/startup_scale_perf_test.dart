import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/blob_references.dart';
import 'package:len/data/notebook_repository.dart';
import 'package:len/features/library/library_controller.dart';

import 'support/big_library.dart';

/// Launching with a years-old database: what runs before the first frame
/// (opening and checking the database, the services, the library's first
/// read and its trash purge) and the housekeeping that follows (blob
/// garbage collection, the handwriting index's queue check, an idle sync).
void main() {
  test('startup with a large database', () async {
    final files = BenchFiles();
    addTearDown(files.dispose);
    final clock = BenchClock();
    var s = openServices(files.dbPath, clock);
    final library = BigLibrary.build(s, clock, coverLines: 25);
    final db = s.database.db;
    // Years of editing: more ink on a twentieth of the other pages (≈ 330k
    // strokes; a 2M-stroke database scales linearly), a tenth of it erased.
    db.execute('''
      INSERT INTO strokes (id, surface_id, tool, color, width, style, points, created_at,
                           updated_at, device_id, deleted, dirty)
      SELECT lower(hex(randomblob(16))), p.id, s.tool, s.color, s.width, s.style, s.points,
             s.created_at, s.updated_at, s.device_id, (abs(random()) % 10 = 0), 0
      FROM strokes s
      JOIN pages f ON f.id = s.surface_id
      JOIN pages p ON p.notebook_id = f.notebook_id AND p.id <> f.id
      WHERE (abs(random()) % 20) = 0''');
    // Pdf and audio blobs: 500 files (5 GB worth of rows; GC reads rows,
    // never the files).
    for (var i = 0; i < 500; i++) {
      db.execute(
        'INSERT INTO blobs (sha256, size, mime, created_at, uploaded) VALUES (?, ?, ?, ?, 1)',
        [i.toRadixString(16).padLeft(64, '0'), 10 << 20, 'application/pdf', clock.nowMs()],
      );
    }
    // The trash's notebooks were deleted long ago: purged at the next start.
    db.execute('UPDATE notebooks SET trashed_at = 1 WHERE trashed_at IS NOT NULL');
    final strokes = db.select('SELECT COUNT(*) AS n FROM strokes').first['n'] as int;
    expect(library.trashed, hasLength(200));
    db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    s.dispose();
    clock.now += NotebookRepository.trashKeptFor.inMilliseconds;

    final timings = <String, int>{};
    void time(String label, void Function() action) {
      final w = Stopwatch()..start();
      action();
      timings[label] = w.elapsedMilliseconds;
    }

    late AppDatabase database;
    time('open database', () => database = AppDatabase.open(files.dbPath));
    time('services', () => s = AppServices.create(database, clock: clock));
    addTearDown(s.dispose);
    late LibraryController controller;
    time('library', () => controller = LibraryController(s));
    // The expired trash goes after the first frame, a notebook at a time.
    final purge = Stopwatch()..start();
    final blocked = await longestTurnUntil(() => controller.trash.isEmpty);
    timings['trash purge (200 notebooks)'] = purge.elapsedMilliseconds;
    timings['longest purge step'] = blocked;
    time('library reload', controller.reload);
    final gc = Stopwatch()..start();
    await s.blobGc.run();
    timings['blob GC (purges 30k old tombstones)'] = gc.elapsedMilliseconds;
    gc.reset();
    await s.blobGc.run();
    timings['blob GC (next day)'] = gc.elapsedMilliseconds;
    time('blob references', () => BlobReferences(s.database).all(tombstonesSince: 0));
    // Old tombstones' payloads are found through an index, not a scan.
    final plan = s.database.db.select(
      'EXPLAIN QUERY PLAN UPDATE strokes SET points = x\'\' '
      'WHERE deleted = 1 AND updated_at < ? AND length(points) > 0',
      [0],
    );
    expect(plan.map((r) => r['detail']).join(), contains('strokes_tombstone_payloads'));
    time('handwriting queue check', () => s.recognition.indexer.pendingCount);

    report('startup, $strokes strokes, ${files.dbBytes >> 20} MB: $timings');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
