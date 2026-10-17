import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/syncable.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/templates/paper_style.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/sync/sync_api.dart';
import 'package:len/sync/sync_engine.dart';
import 'package:len_sync_server/len_sync_server.dart' as server;

import 'support/live_devices.dart';
import 'support/real_server.dart';

// The pieces of live sync over `/v1/live` (sync_live_test.dart has them
// together): what the engine pushes and applies, the messages, and how an
// open surface takes in a stroke written elsewhere.

Stroke _stroke(AppServices s, String surface, {double x = 10}) => Stroke(
  id: s.clock.newId(),
  surfaceId: surface,
  tool: InkTool.ballpoint,
  color: 0xFF000000,
  width: 2,
  points: [StrokePoint(x, 10, 0.5), StrokePoint(x + 20, 30, 0.5)],
  createdAt: s.clock.nowMs(),
);

Notebook _notebook(AppServices s) => s.notebooks.create(
  title: 'Live',
  kind: NotebookKind.paged,
  paper: PaperStyle.blank,
  coverColor: 0xFF000000,
);

void main() {
  group('LiveMessage', () {
    test('parses what the server sends, and anything else as a sign of life', () {
      expect(
        LiveMessage.parse('{"type":"hello","serverId":"s","seq":4,"connection":"c1"}'),
        isA<LiveHello>().having((m) => m.seq, 'seq', 4).having((m) => m.connection, 'id', 'c1'),
      );
      final records = LiveMessage.parse(
        jsonEncode({
          'type': 'records',
          'prevSeq': 4,
          'seq': 6,
          'records': [
            {
              'collection': 'folders',
              'id': 'f',
              'updatedAt': 1,
              'deviceId': 'd',
              'deleted': true,
              'data': null,
              'seq': 5,
            },
            {'collection': 'BAD'},
          ],
        }),
      );
      expect(records, isA<LiveRecords>());
      records as LiveRecords;
      expect(records.records.single.id, 'f');
      expect(records.malformed, 1);
      expect(
        LiveMessage.parse('{"type":"records","prevSeq":6,"seq":6,"records":[]}'),
        isA<LiveOther>(),
      );
      expect(LiveMessage.parse('{"type":"resync","seq":9}'), isA<LiveResync>());
      expect(
        LiveMessage.parse('{"type":"pushed","id":3,"stale":true,"serverSeq":9}'),
        isA<LivePushed>().having((m) => m.stale, 'stale', isTrue),
      );
      expect(
        LiveMessage.parse(
          '{"type":"presence","room":"n","members":[{"connection":"c1","deviceId":"d"},{"x":1}]}',
        ),
        isA<LivePresence>().having((m) => m.members.length, 'members', 1),
      );
      expect(LiveMessage.parse('not json'), isA<LiveOther>());
      expect(LiveMessage.parse('{"type":"heartbeat"}'), isA<LiveOther>());
    });
  });

  group('engine', () {
    late RealServer real;
    late AppServices a;
    late SyncApi api;

    setUp(() async {
      real = RealServer();
      a = AppServices.create(AppDatabase.inMemory());
      api = SyncApi(baseUrl: 'http://sync.test', token: RealServer.token, client: real.client);
      addTearDown(() {
        a.dispose();
        real.dispose();
      });
      await a.sync.engine.sync(api); // The first sync: now it may go live.
      expect(a.sync.engine.liveReady(real.store.serverId), isTrue);
    });

    /// A [LivePush] storing on [real] as its live connection would.
    final sent = <({List<String> ids, bool current})>[];
    Future<LivePushed> send(
      List<SyncRecord> records, {
      required int since,
      required bool current,
    }) async {
      sent.add((ids: [for (final r in records) r.id], current: current));
      final result = real.store.push([
        for (final r in records) server.SyncRecord.fromJson(jsonDecode(jsonEncode(r.toJson()))),
      ], since: since);
      return LivePushed(id: 0, applied: result.applied, serverSeq: result.serverSeq);
    }

    setUp(sent.clear);

    test('pushes live rows, then deletions as "current" pushes; marks them clean', () async {
      final keep = a.folders.create(name: 'Keep', color: 1);
      final gone = a.folders.create(name: 'Gone', color: 1);
      expect(await a.sync.engine.pushLive(send), LivePushOutcome.done);
      a.folders.delete(gone.id);
      a.folders.update(keep.copyWith(name: 'Kept'));
      expect(await a.sync.engine.pushLive(send), LivePushOutcome.done);
      expect(sent.first.ids, unorderedEquals([keep.id, gone.id]));
      expect(
        [for (final s in sent.skip(1)) '${s.current}: ${s.ids.join(',')}'],
        ['false: ${keep.id}', 'true: ${gone.id}'],
      );
      expect(a.sync.engine.hasDirtyRows(), isFalse);
      // Its own seqs follow on from what it pulled.
      expect(a.sync.engine.knownSeq, real.store.currentSeq());
    });

    test('a stale answer leaves the rows dirty', () async {
      final f = a.folders.create(name: 'F', color: 1);
      await a.sync.engine.pushLive(send);
      a.folders.delete(f.id);
      final outcome = await a.sync.engine.pushLive(
        (records, {required since, required current}) async =>
            LivePushed(id: 0, applied: 0, serverSeq: since + 1, stale: true),
      );
      expect(outcome, LivePushOutcome.stale);
      expect(a.sync.engine.hasDirtyRows(), isTrue);
    });

    test('a failed push leaves the rows to a run', () async {
      a.folders.create(name: 'F', color: 1);
      final outcome = await a.sync.engine.pushLive(
        (records, {required since, required current}) async =>
            throw const LivePushException('connection closed'),
      );
      expect(outcome, LivePushOutcome.needsRun);
      expect(a.sync.engine.hasDirtyRows(), isTrue);
    });

    test('a record whose blob is not uploaded yet waits for a run', () async {
      final nb = _notebook(a);
      final first = a.pages.pagesOf(nb.id).first;
      final sha = await a.blobs.putBytes(utf8.encode('a scan'), mime: 'image/png');
      final page = a.pages.insertPages(nb.id, [
        (
          size: const Size(800, 1100),
          paper: first.paper,
          color: first.paperColor,
          background: PageBackground.image(blob: sha),
        ),
      ]).single;
      expect(await a.sync.engine.pushLive(send), LivePushOutcome.needsRun);
      expect(sent.expand((s) => s.ids), isNot(contains(page.id)));
      expect(sent.expand((s) => s.ids), contains(nb.id));
    });

    test('applies records that follow on; a gap is left to a pull', () async {
      final known = a.sync.engine.knownSeq;
      LiveRecords folder(String id, int prev, int seq) => LiveRecords(
        prevSeq: prev,
        seq: seq,
        records: [
          SyncRecord(
            collection: 'folders',
            id: id,
            updatedAt: 5,
            deviceId: 'zz',
            deleted: false,
            data: {'name': id, 'parentId': null, 'color': 0, 'createdAt': 1},
          ),
        ],
      );
      expect(await a.sync.engine.applyLive(folder('gap', known + 1, known + 2)), isNull);
      expect(a.folders.get('gap'), isNull);
      final changes = await a.sync.engine.applyLive(folder('next', known, known + 1));
      expect(changes!.folders, isTrue);
      expect(a.folders.get('next'), isNotNull);
      expect(a.settings.syncLastSeq, known + 1);
      // Seen already: nothing to do.
      final again = await a.sync.engine.applyLive(folder('next', known, known + 1));
      expect(again!.isEmpty, isTrue);
    });
  });

  test('an open surface takes in a stroke from elsewhere without reloading', () {
    final a = AppServices.create(AppDatabase.inMemory());
    final b = AppServices.create(AppDatabase.inMemory());
    addTearDown(() {
      a.dispose();
      b.dispose();
    });
    final page = b.pages.pagesOf(_notebook(b).id).first;
    final model = SurfaceModel(
      surfaceId: page.id,
      repository: b.strokes,
      elementRepository: b.elements,
    )..ensureLoaded(const Rect.fromLTWH(0, 0, 800, 1100));
    addTearDown(model.dispose);
    final mine = _stroke(b, page.id, x: 100);
    model.addStroke(mine);
    final changes = <SurfaceChange>[];
    model.changes.listen(changes.add);

    // Another device's stroke arrives (as sync applies it).
    final theirs = _stroke(a, page.id, x: 400);
    a.strokes.save([theirs]);
    b.strokes.applyRemote(a.strokes.dirtyRecords(10).single);
    final remote = RemoteChanges()..addItem(page.id, theirs.id);
    model.refreshItems(remote.itemsOf(page.id)!);
    expect(model.strokeById(theirs.id), isNotNull);
    expect(model.strokeById(mine.id), isNotNull);
    expect(changes.single.chunks, isNotNull, reason: 'only its chunks');
    expect(changes.single.appended, hasLength(1), reason: 'drawn over what was there');

    // And erased there.
    a.strokes.markClean([(id: theirs.id, updatedAt: a.strokes.dirtyRecords(10).single.updatedAt)]);
    a.strokes.delete([theirs.id]);
    b.strokes.applyRemote(a.strokes.dirtyRecords(10).single);
    model.refreshItems({theirs.id});
    expect(model.strokeById(theirs.id), isNull);
    expect(model.strokeById(mine.id), isNotNull);
    expect(changes.last.chunks, isNotNull);
    expect(model.history.canUndo, isTrue, reason: 'its own edits stay undoable');
  });

  liveTest('a gap in what the connection brings is pulled', (l) {
    final a = l.device('a');
    l.wait(const Duration(seconds: 3));
    final runs = Runs(a.s.sync);
    // Records far ahead of what A knows (as after messages it never got).
    final stored = l.server.store.push([
      server.SyncRecord.fromJson({
        'collection': 'folders',
        'id': 'far',
        'updatedAt': 1,
        'deviceId': 'zz',
        'deleted': false,
        'data': {'name': 'Far', 'parentId': null, 'color': 0, 'createdAt': 1},
      }),
    ]);
    l.server.live.publishRecords([stored.stored.single.withSeq(stored.serverSeq + 5)]);
    l.until(() => a.s.folders.get('far') != null, limit: const Duration(seconds: 3));
    expect(runs.count, 1);
    expect(a.s.sync.settings.syncLastSeq, l.server.store.currentSeq());
  });
}
