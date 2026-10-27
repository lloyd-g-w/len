import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/sync/background_pull_worker.dart';
import 'package:len/sync/pull_applier.dart';
import 'package:len/sync/pull_worker.dart';
import 'package:len/sync/sync_engine.dart';

import 'support/fake_server.dart';
import 'support/test_database.dart';
import 'support/two_devices.dart';

/// The pull worker's isolate dying, or outliving the app's: a pull never
/// waits for a worker that is gone, and a worker never lives on orphaned.
void main() {
  late Directory dir;
  var databases = 0;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('len-pull-life-');
    openTestDatabase = () => AppDatabase.open('${dir.path}/${databases++}.db');
    SyncEngine.workerFromBytes = 0;
  });
  tearDown(() {
    openTestDatabase = AppDatabase.inMemory;
    SyncEngine.workerFromBytes = 64 * 1024;
    BackgroundPullWorker.debugOnServe = null;
    dir.deleteSync(recursive: true);
  });

  test('a worker dying before it is ready: the pull runs here instead', () async {
    final (a, b) = twoDevices();
    _fill(a, strokes: 50);
    await a.sync();
    BackgroundPullWorker.debugOnServe = _die;
    await b.sync().timeout(const Duration(seconds: 20));
    expect(_count(b, 'strokes'), 50);
    expect(b.s.database.writeSignal, isNull);
  });

  test('a worker dying between pages fails the next one instead of hanging', () async {
    final (a, b) = twoDevices();
    _fill(a, strokes: 50);
    await a.sync();
    final worker = (await BackgroundPullWorker.start(b.s.database, deviceId: 'b'))!;
    final exited = ReceivePort();
    worker.isolate.addOnExitListener(exited.sendPort);
    worker.isolate.kill(priority: Isolate.immediate);
    await exited.first;
    exited.close();
    final body = await apiFor(a.server).pullBody(since: 0);
    await expectLater(
      worker
          .apply(body, since: 0, hadChanges: false, onHeader: (_) {}, cancelled: () => false)
          .timeout(const Duration(seconds: 20)),
      throwsA(isA<PullWorkerException>()),
    );
    await worker.close();
    expect(b.s.database.writeSignal, isNull);
  });

  test('a worker dying while it applies a page fails it instead of hanging', () async {
    // A page long enough to apply (a record a slice) that the kill, sent
    // when its header comes, lands before the end even on a busy machine
    // (with 50 records in one slice the worker could finish first).
    PullApplier.debugSliceRecords = 1;
    addTearDown(() => PullApplier.debugSliceRecords = null);
    final (a, b) = twoDevices();
    _fill(a, strokes: 600);
    await a.sync();
    final worker = (await BackgroundPullWorker.start(b.s.database, deviceId: 'b'))!;
    final body = await apiFor(a.server).pullBody(since: 0);
    await expectLater(
      worker
          .apply(
            body,
            since: 0,
            hadChanges: false,
            onHeader: (_) => worker.isolate.kill(priority: Isolate.immediate),
            cancelled: () => false,
          )
          .timeout(const Duration(seconds: 20)),
      throwsA(isA<PullWorkerException>()),
    );
    await worker.close();
  });

  test("a worker exits with the app's isolate, closing its connection", () async {
    final path = '${dir.path}/owner.db';
    AppDatabase.open(path).close();
    final exited = ReceivePort();
    // An isolate standing in for the app's: it starts a worker and exits
    // (as the engine's does when Android destroys it) without closing it.
    await Isolate.spawn(_startWorkerAndExit, (path, exited.sendPort));
    await exited.first.timeout(const Duration(seconds: 20));
    exited.close();
    // The last connection closed checkpoints the log and removes it.
    expect(File('$path-wal').existsSync(), isFalse);
  });
}

void _die() => throw StateError('the worker died');

Future<void> _startWorkerAndExit((String, SendPort) args) async {
  final (path, exited) = args;
  final database = AppDatabase.open(path);
  final worker = (await BackgroundPullWorker.start(database, deviceId: 'x'))!;
  // Added while the worker surely lives: it waits for its owner's exit.
  worker.isolate.addOnExitListener(exited);
  database.close();
  Isolate.exit();
}

int _count(TestDevice d, String table) =>
    d.db.select('SELECT COUNT(*) AS n FROM $table').first['n'] as int;

void _fill(TestDevice d, {required int strokes}) {
  final s = d.s;
  final nb = s.notebooks.create(
    title: 'Notebook',
    kind: NotebookKind.paged,
    paper: PaperStyle.collegeRuled,
    coverColor: 0,
  );
  final page = s.pages.pagesOf(nb.id).first;
  s.strokes.save([
    for (var i = 0; i < strokes; i++)
      Stroke(
        id: d.clock.newId(),
        surfaceId: page.id,
        tool: InkTool.ballpoint,
        color: 0xFF000000,
        width: 2,
        points: [for (var k = 0; k < 4; k++) StrokePoint(10.0 + k * 3, 20.0 + i, 0.5)],
        createdAt: i,
      ),
  ]);
}
