import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/sync/sync_engine.dart';
import 'package:sqlite3/sqlite3.dart';

import 'support/fake_server.dart';
import 'support/test_database.dart';
import 'support/two_devices.dart';
import 'sync_delete_race_test.dart' as delete_race;
import 'sync_properties_test.dart' as properties;
import 'sync_recovery_test.dart' as recovery;

/// The sync tests again with every device's database in a file and every
/// pull applied by a worker isolate over its own connection (as natively
/// for a first sync), and what only the worker does: the app writing
/// meanwhile, its commits heard, triggers firing there.
void main() {
  late Directory dir;
  var databases = 0;
  setUpAll(() {
    dir = Directory.systemTemp.createTempSync('len-pull-worker-');
    openTestDatabase = () => AppDatabase.open('${dir.path}/${databases++}.db');
    SyncEngine.workerFromBytes = 0;
  });
  tearDownAll(() {
    openTestDatabase = AppDatabase.inMemory;
    SyncEngine.workerFromBytes = 64 * 1024;
    dir.deleteSync(recursive: true);
  });

  group('in a worker:', () {
    delete_race.main();
    recovery.main();
    properties.main();
  });

  test('a pull in a worker: the app writes meanwhile, triggers fire', () async {
    final (a, b) = twoDevices();
    _fill(a, notebooks: 6, strokesEach: 400);
    await a.sync();
    var done = false;
    final pulling = b.sync().whenComplete(() => done = true);
    var writes = 0;
    var inWorker = false;
    while (!done) {
      inWorker |= b.s.database.writeSignal != null;
      // A transaction of the app's own while the worker writes.
      b.s.database.transaction(
        () => b.s.database.execute(
          "INSERT OR REPLACE INTO settings (key, value) VALUES ('test_write', ?)",
          ['${writes++}'],
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    final changes = await pulling;
    expect(changes.notebooks, isTrue);
    expect(changes.strokeSurfaces, hasLength(6));
    expect(_count(b, 'strokes'), 2400);
    expect(_count(a, 'strokes'), 2400);
    expect(writes, greaterThan(0));
    expect(inWorker, isTrue, reason: 'applied by a worker');
    expect(b.s.database.writeSignal, isNull, reason: 'the worker is gone');
    // Triggers ran on the worker's connection: pages queued for handwriting
    // recognition (the indexer waits seconds of quiet first), search kept.
    expect(_count(b, 'ink_text_queue'), 6);
    expect(_count(b, 'search_docs'), _count(a, 'search_docs'));
    expect(_count(b, 'search_docs'), greaterThan(0));
  });

  test("a worker's commits are announced to the app's listeners", () async {
    final (a, b) = twoDevices();
    await b.sync(); // Its own first-sync bookkeeping done.
    _fill(a, notebooks: 2, strokesEach: 50);
    await a.sync();
    var commits = 0, own = 0;
    final heard = b.s.database.commits.listen((_) => commits++);
    final ownHeard = b.db.commits.listen((_) => own++);
    addTearDown(heard.cancel);
    addTearDown(ownHeard.cancel);
    await b.sync();
    await Future<void>.delayed(Duration.zero);
    expect(_count(b, 'strokes'), 100);
    expect(commits, greaterThan(own), reason: "the worker's as well as the app's own");
  });

  test('a pull in a worker waits out a write lock held longer than the busy timeout', () async {
    final (a, b) = twoDevices();
    _fill(a, notebooks: 4, strokesEach: 600);
    await a.sync();
    var done = false;
    final pulling = b.sync().whenComplete(() => done = true);
    while (b.s.database.writeSignal == null) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    // Another writer (a long transaction) holds the lock between slices.
    final other = sqlite3.open(b.s.database.path!)
      ..execute('PRAGMA busy_timeout = ${AppDatabase.busyTimeoutMs}')
      ..execute('BEGIN IMMEDIATE');
    expect(done, isFalse, reason: 'the lock taken while the worker pulls');
    await Future<void>.delayed(const Duration(milliseconds: AppDatabase.busyTimeoutMs + 1500));
    other
      ..execute('COMMIT')
      ..close();
    await pulling;
    expect(_count(b, 'strokes'), 2400);
  });

  test('a pull in a worker stops when cancelled and picks up where it was', () async {
    final (a, b) = twoDevices();
    _fill(a, notebooks: 4, strokesEach: 600);
    await a.sync();
    var cancel = false;
    final pulls = a.server.pulls;
    final first = b.s.sync.engine.sync(
      apiFor(a.server),
      isCancelled: () {
        // Once a second page was asked for, the first is being applied.
        if (a.server.pulls >= pulls + 2) cancel = true;
        return cancel;
      },
    );
    await first;
    final partial = _count(b, 'strokes');
    expect(partial, lessThan(2400));
    await b.sync();
    expect(_count(b, 'strokes'), 2400);
  });
}

int _count(TestDevice d, String table) =>
    d.db.select('SELECT COUNT(*) AS n FROM $table').first['n'] as int;

void _fill(TestDevice d, {required int notebooks, required int strokesEach}) {
  final s = d.s;
  for (var n = 0; n < notebooks; n++) {
    final nb = s.notebooks.create(
      title: 'Notebook $n',
      kind: NotebookKind.paged,
      paper: PaperStyle.collegeRuled,
      coverColor: 0,
    );
    final page = s.pages.pagesOf(nb.id).first;
    s.strokes.save([
      for (var i = 0; i < strokesEach; i++)
        Stroke(
          id: d.clock.newId(),
          surfaceId: page.id,
          tool: InkTool.ballpoint,
          color: 0xFF000000,
          width: 2,
          points: [
            for (var k = 0; k < 8; k++) StrokePoint(10.0 + k * 3 + i % 50, 20.0 + i ~/ 50 * 9, 0.5),
          ],
          createdAt: i,
        ),
    ]);
  }
}
