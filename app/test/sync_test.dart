import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/chunk_grid.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/sync/sync_api.dart';
import 'package:len/sync/sync_controller.dart';

import 'support/fake_server.dart';

void main() {
  test('two devices converge: create, draw, erase, delete', () async {
    final server = FakeServer();
    final a = device(server);
    final b = device(server);

    final nb = a.notebooks.create(
      title: 'Shared',
      kind: NotebookKind.canvas,
      paper: PaperStyle.grid,
      coverColor: 0xFF00FF00,
    );
    a.strokes.save([
      Stroke(
        id: 'ink-1',
        surfaceId: nb.id,
        tool: InkTool.pen,
        color: 0xFF000000,
        width: 3,
        points: const [StrokePoint(1, 2, 0.25), StrokePoint(30, 40, 0.75)],
        createdAt: 1,
      ),
    ]);

    await a.sync.engine.sync(apiFor(server));
    final changes = await b.sync.engine.sync(apiFor(server));

    expect(changes.notebooks, isTrue);
    expect(changes.strokeSurfaces, {nb.id});
    expect(b.notebooks.list().single.title, 'Shared');
    final keys = b.strokes.populatedChunks(
      nb.id,
      ChunkGrid.rangeFor(const Rect.fromLTRB(-1000, -1000, 1000, 1000)),
    );
    final synced = b.strokes.loadChunks(nb.id, keys).single;
    expect(synced.points.last, const StrokePoint(30, 40, 0.75));
    expect(synced.bounds.contains(const Offset(30, 40)), isTrue);

    // B erases the stroke; A learns about it.
    b.strokes.delete(['ink-1']);
    await b.sync.engine.sync(apiFor(server));
    await a.sync.engine.sync(apiFor(server));
    expect(a.strokes.loadChunks(nb.id, keys), isEmpty);

    // A deletes the notebook; B learns about it.
    a.notebooks.delete(nb.id);
    await a.sync.engine.sync(apiFor(server));
    await b.sync.engine.sync(apiFor(server));
    expect(b.notebooks.list(), isEmpty);

    // Nothing left to push on either side.
    expect(a.strokes.dirtyRecords(10), isEmpty);
    expect(b.notebooks.dirtyRecords(10), isEmpty);
  });

  test('a wrong token surfaces as a SyncException', () async {
    final server = FakeServer();
    final api = SyncApi(baseUrl: 'http://sync.test', token: 'nope', client: server.client);
    await expectLater(api.check(), throwsA(isA<SyncException>()));
  });

  test('pushes are split to stay under the size and count limits', () async {
    final server = FakeServer();
    final a = device(server);
    // 600 strokes of ~16 KB base64 each: ~10 MB, more than one 4 MiB request.
    a.strokes.save([for (var i = 0; i < 600; i++) bigStroke('s$i', 'canvas', 1000)]);

    await a.sync.engine.sync(apiFor(server));

    expect(server.pushes.length, greaterThan(2));
    expect(server.pushes.every((p) => p.bytes <= SyncApi.pushBytesTarget), isTrue);
    expect(server.pushes.fold<int>(0, (n, p) => n + p.count), 600);
    expect(a.strokes.dirtyRecords(1000), isEmpty);
  });

  test('malformed pulled records are skipped and the feed advances', () async {
    final server = FakeServer();
    final a = device(server);
    a.notebooks.create(
      title: 'ok',
      kind: NotebookKind.canvas,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    await a.sync.engine.sync(apiFor(server));

    server.injected.addAll([
      'not an object',
      {'collection': 'strokes', 'id': 'x', 'updatedAt': 1, 'deviceId': 'd', 'deleted': false},
      {
        'collection': 'strokes',
        'id': 'y',
        'updatedAt': 1,
        'deviceId': 'd',
        'deleted': false,
        'data': {
          'surfaceId': 's',
          'tool': 'pen',
          'color': 0,
          'width': 1,
          'points': '!!',
          'createdAt': 0,
        },
      },
      {
        'collection': 'pages',
        'id': 'z',
        'updatedAt': 1,
        'deviceId': 'd',
        'deleted': false,
        'data': {'notebookId': 'n'},
      },
      {
        'collection': 'future_things',
        'id': 'f',
        'updatedAt': 1,
        'deviceId': 'd',
        'deleted': false,
        'data': {},
      },
    ]);
    final b = device(server);
    await b.sync.engine.sync(apiFor(server));

    expect(b.notebooks.list().single.title, 'ok');
    expect(b.settings.syncLastSeq, greaterThan(0));
    expect(b.strokes.surfaceOf('y'), isNull);
  });

  test('a pull page that does not advance is rejected', () async {
    final api = SyncApi(
      baseUrl: 'http://sync.test',
      token: 't',
      client: MockClient((_) async => pullResponse([], nextSince: 5, hasMore: true)),
    );
    await expectLater(api.pull(since: 5), throwsA(isA<SyncException>()));
  });

  test('invalid server URLs are rejected with a readable message', () {
    for (final url in ['', 'sync.example.com', 'ftp://x', 'http://']) {
      expect(
        () => SyncApi(baseUrl: url, token: 't'),
        throwsA(isA<SyncException>()),
        reason: url,
      );
    }
  });

  test('server errors show the error field, not the raw body', () async {
    final api = SyncApi(
      baseUrl: 'http://sync.test/',
      token: 't',
      client: MockClient((_) async => http.Response('<html>${'x' * 10000}</html>', 502)),
    );
    await expectLater(
      api.check(),
      throwsA(isA<SyncException>().having((e) => e.message, 'message', 'Sync server error 502')),
    );
  });

  group('SyncController', () {
    test('switching servers re-uploads everything from seq 0', () async {
      final first = FakeServer();
      final second = FakeServer();
      var target = first;
      final a = AppServices.create(AppDatabase.inMemory());
      final controller = SyncController(
        engine: a.sync.engine,
        settings: a.settings,
        apiFactory: (url, token) => SyncApi(baseUrl: url, token: token, client: target.client),
      );
      controller.configure(url: 'http://one.test', token: FakeServer.token);
      a.notebooks.create(
        title: 'N',
        kind: NotebookKind.canvas,
        paper: PaperStyle.blank,
        coverColor: 0,
      );
      await controller.syncNow();
      expect(controller.state, SyncState.idle);
      expect(a.settings.syncLastSeq, 1);

      // Same server with a trailing slash is not a switch.
      controller.configure(url: 'http://one.test/', token: FakeServer.token);
      expect(a.notebooks.dirtyRecords(10), isEmpty);

      target = second;
      controller.configure(url: 'http://two.test', token: FakeServer.token);
      expect(a.settings.syncLastSeq, 0);
      await controller.syncNow();
      expect(second.pushes.single.count, 1);
      controller.dispose();
    });

    test('concurrent syncNow calls coalesce into one follow-up run', () async {
      final server = FakeServer();
      final a = AppServices.create(AppDatabase.inMemory());
      final controller = SyncController(
        engine: a.sync.engine,
        settings: a.settings,
        apiFactory: (url, token) => SyncApi(baseUrl: url, token: token, client: server.client),
      );
      controller.configure(url: 'http://sync.test', token: FakeServer.token);
      final runs = [controller.syncNow(), controller.syncNow(), controller.syncNow()];
      await Future.wait(runs);
      expect(server.pulls, 2);
      expect(controller.state, SyncState.idle);
      controller.dispose();
    });

    test('disposing during a sync neither throws nor writes', () async {
      final server = FakeServer();
      final a = AppServices.create(AppDatabase.inMemory());
      final controller = SyncController(
        engine: a.sync.engine,
        settings: a.settings,
        apiFactory: (url, token) => SyncApi(baseUrl: url, token: token, client: server.client),
      );
      controller.configure(url: 'http://sync.test', token: FakeServer.token);
      a.notebooks.create(
        title: 'N',
        kind: NotebookKind.canvas,
        paper: PaperStyle.blank,
        coverColor: 0,
      );
      final run = controller.syncNow();
      controller.dispose();
      await run;
      expect(a.notebooks.dirtyRecords(10), hasLength(1)); // not marked clean
    });

    test('unexpected errors end in the error state', () async {
      final a = AppServices.create(AppDatabase.inMemory());
      final controller = SyncController(
        engine: a.sync.engine,
        settings: a.settings,
        apiFactory: (url, token) => throw StateError('boom'),
      );
      controller.configure(url: 'http://sync.test', token: FakeServer.token);
      await controller.syncNow();
      expect(controller.state, SyncState.error);
      expect(controller.lastError, contains('boom'));
      controller.dispose();
    });
  });
}
