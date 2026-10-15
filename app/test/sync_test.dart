import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:len/app_services.dart';
import 'package:len/core/clock.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/syncable.dart';
import 'package:len/domain/chunk_grid.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/library/library_controller.dart';
import 'package:len/sync/sync_api.dart';
import 'package:len/sync/sync_controller.dart';

import 'support/fake_server.dart';

http.Request _copy(http.BaseRequest request) => http.Request(request.method, request.url)
  ..headers.addAll(request.headers)
  ..bodyBytes = (request as http.Request).bodyBytes;

/// A clock moving a minute on with every reading.
class _SteppingClock extends Clock {
  int _ms = 0;

  @override
  int nowMs() => _ms += 60000;
}

void main() {
  test('two devices converge: create, draw, erase, delete', () async {
    final server = FakeServer();
    final a = device(server);
    final b = device(server);

    final nb = a.notebooks.create(
      title: 'Shared',
      kind: NotebookKind.canvas,
      paper: PaperStyle.gridLarge,
      coverColor: 0xFF00FF00,
    );
    a.strokes.save([
      Stroke(
        id: 'ink-1',
        surfaceId: nb.id,
        tool: InkTool.ballpoint,
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

  test('a record JSON cannot encode is skipped, the others are pushed', () async {
    final server = FakeServer();
    SyncRecord record(String id, double x) => SyncRecord(
      collection: 'elements',
      id: id,
      updatedAt: 1,
      deviceId: 'd',
      deleted: false,
      data: {'x': x},
    );
    final unsent = await apiFor(server)
        .push([record('bad', double.nan), record('ok', 1)], since: 0);
    expect(unsent.single.id, 'bad');
    expect(server.stored('elements', 'ok'), isNotNull);
    expect(server.stored('elements', 'bad'), isNull);
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
          'tool': 'ballpoint',
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

  test('a token that cannot travel in a header is explained', () {
    for (final token in ['tökén', 'two words', 'line\nbreak']) {
      expect(
        () => SyncApi(baseUrl: 'http://sync.test', token: token),
        throwsA(isA<SyncException>().having((e) => e.kind, 'kind', SyncFailure.auth)),
        reason: token,
      );
    }
  });

  test('server errors show the error field, not the raw body', () async {
    final api = SyncApi(
      baseUrl: 'http://sync.test/',
      token: 't',
      client: MockClient((_) async => http.Response('<html>${'x' * 10000}</html>', 500)),
    );
    await expectLater(
      api.check(),
      throwsA(isA<SyncException>().having((e) => e.message, 'message', 'Sync server error 500')),
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
        tokens: a.sync.tokens,
        apiFactory: (url, token) => SyncApi(baseUrl: url, token: token, client: target.client),
      );
      final notices = <String>[];
      controller.notices.listen(notices.add);
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

      // Another address of the same server (same id) is not a switch.
      controller.configure(url: 'http://192.168.1.10:8080/', token: FakeServer.token);
      await controller.syncNow();
      expect(first.pushes, hasLength(1));
      expect(notices, isEmpty, reason: 'nothing to explain on the first sync');

      target = second;
      controller.configure(url: 'http://two.test', token: FakeServer.token);
      await controller.syncNow();
      expect(controller.state, SyncState.idle);
      expect(second.pushes.single.count, 1);
      expect(a.settings.syncServerId, second.serverId);
      await controller.syncNow();
      expect(notices, ['The sync server changed, so everything was synced again']);
      controller.dispose();
    });

    test(
      'a long first pull says how far it is and fills the library in as it goes (R16-5)',
      () async {
        final server = FakeServer()..maxPage = 3;
        final a = device(server);
        for (var i = 0; i < 6; i++) {
          a.notebooks.create(
            title: 'N$i',
            kind: NotebookKind.paged,
            paper: PaperStyle.blank,
            coverColor: 0,
          );
        }
        await a.sync.engine.sync(apiFor(server));
        final b = AppServices.create(AppDatabase.inMemory());
        final controller = SyncController(
          engine: b.sync.engine,
          settings: b.settings,
          tokens: b.sync.tokens,
          apiFactory: (url, token) => SyncApi(baseUrl: url, token: token, client: server.client),
        );
        final progress = <double?>[];
        final arriving = <bool>[];
        controller.addListener(() {
          progress.add(controller.progress);
          arriving.add(controller.firstSyncUnderWay);
        });
        final announced = <int>[];
        controller.remoteChanges.listen((c) {
          if (c.notebooks) announced.add(b.notebooks.list().length);
        });
        controller.configure(url: 'http://sync.test', token: FakeServer.token);
        await controller.syncNow();
        await pumpEventQueue();
        expect(progress.whereType<double>(), isNotEmpty);
        expect(progress.whereType<double>().every((p) => p > 0 && p < 1), isTrue);
        expect(progress.last, isNull); // Done.
        expect(arriving, contains(true));
        expect(controller.firstSyncUnderWay, isFalse);
        // The library heard of some notebooks before the last one arrived.
        expect(announced.length, greaterThanOrEqualTo(2));
        expect(announced.first, lessThan(6));
        expect(announced.last, 6);
        controller.dispose();
      },
    );

    test('the percentage never goes back when another device pushes during a pull', () async {
      final server = FakeServer()..maxPage = 3;
      final a = device(server);
      void write(int n) {
        for (var i = 0; i < n; i++) {
          a.notebooks.create(
            title: 'N$i',
            kind: NotebookKind.canvas,
            paper: PaperStyle.blank,
            coverColor: 0,
          );
        }
      }

      write(12);
      await a.sync.engine.sync(apiFor(server));
      final b = AppServices.create(AppDatabase.inMemory());
      var pulls = 0;
      final controller = SyncController(
        engine: b.sync.engine,
        settings: b.settings,
        tokens: b.sync.tokens,
        apiFactory: (url, token) => SyncApi(
          baseUrl: url,
          token: token,
          client: MockClient((request) async {
            if (request.url.path == '/v1/pull' && ++pulls == 3) {
              write(30); // The feed more than doubles mid-pull.
              await a.sync.engine.sync(apiFor(server));
            }
            return http.Response.fromStream(await server.client.send(_copy(request)));
          }),
        ),
      );
      final progress = <double>[];
      controller.addListener(() {
        if (controller.progress case final p?) progress.add(p);
      });
      controller.configure(url: 'http://sync.test', token: FakeServer.token);
      await controller.syncNow();
      expect(b.notebooks.list(), hasLength(42));
      expect(progress.length, greaterThan(2));
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i], greaterThanOrEqualTo(progress[i - 1]), reason: '$progress');
      }
      controller.dispose();
    });

    test('a long pull reloads the library only after it brought notebooks or folders', () async {
      final server = FakeServer()..maxPage = 3;
      final a = device(server);
      final nb = a.notebooks.create(
        title: 'Big',
        kind: NotebookKind.canvas,
        paper: PaperStyle.blank,
        coverColor: 0,
      );
      await a.sync.engine.sync(apiFor(server));
      a.strokes.save([for (var i = 0; i < 30; i++) bigStroke('s$i', nb.id, 4)]);
      await a.sync.engine.sync(apiFor(server));
      final b = AppServices.create(AppDatabase.inMemory());
      final controller = SyncController(
        engine: b.sync.engine,
        settings: b.settings,
        tokens: b.sync.tokens,
        clock: _SteppingClock(), // Every progress report is long after the last.
        apiFactory: (url, token) => SyncApi(baseUrl: url, token: token, client: server.client),
      );
      var announced = 0;
      controller.remoteChanges.listen((_) => announced++);
      controller.configure(url: 'http://sync.test', token: FakeServer.token);
      await controller.syncNow();
      await pumpEventQueue();
      // Mid-pull: once, for the notebook on the first page (not for each of
      // the ten pages of strokes after it); then the run's own.
      expect(announced, 2);
      controller.dispose();
    });

    test('the library hears of the first sync until the pull ends, not its first page', () async {
      final server = FakeServer()..maxPage = 3;
      final a = device(server);
      final nb = a.notebooks.create(
        title: 'Lab',
        kind: NotebookKind.paged,
        paper: PaperStyle.blank,
        coverColor: 0,
      );
      final page = a.pages.addFreshPage(nb);
      a.strokes.save([
        for (var i = 0; i < 12; i++)
          Stroke(
            id: 's$i',
            surfaceId: page.id,
            tool: InkTool.ballpoint,
            color: 0xFF000000,
            width: 2,
            points: const [StrokePoint(1, 2, 0.5), StrokePoint(3, 4, 0.5)],
            createdAt: 1,
          ),
      ]);
      await a.sync.engine.sync(apiFor(server));
      // Written in again later: the notebook's record moves to the feed's end.
      a.notebooks.touch(nb.id);
      await a.sync.engine.sync(apiFor(server));

      final b = AppServices.create(AppDatabase.inMemory());
      final controller = SyncController(
        engine: b.sync.engine,
        settings: b.settings,
        tokens: b.sync.tokens,
        apiFactory: (url, token) => SyncApi(baseUrl: url, token: token, client: server.client),
      );
      final wrong = <String>[];
      controller.addListener(() {
        if (controller.state == SyncState.syncing &&
            b.notebooks.list().isEmpty &&
            !controller.firstSyncUnderWay) {
          wrong.add('empty library, syncing, progress ${controller.progress}, not "arriving"');
        }
      });
      controller.configure(url: 'http://sync.test', token: FakeServer.token);
      await controller.syncNow();
      await pumpEventQueue();
      expect(b.notebooks.list(), hasLength(1));
      expect(wrong, isEmpty);
      controller.dispose();
    });

    test('the library lists a notebook arriving mid-pull once its pages are here', () async {
      final server = FakeServer()..maxPage = 2;
      final a = device(server);
      // Several notebooks: their records come first, their pages after.
      final all = [
        for (var i = 0; i < 3; i++)
          a.notebooks.create(
            title: 'Lab $i',
            kind: NotebookKind.paged,
            paper: PaperStyle.blank,
            coverColor: 0,
          ),
      ];
      for (final n in all) {
        while (a.pages.pagesOf(n.id).length < 4) {
          a.pages.addFreshPage(n);
        }
      }
      await a.sync.engine.sync(apiFor(server));

      final b = AppServices.create(
        AppDatabase.inMemory(),
        syncApiFactory: (url, token) => SyncApi(baseUrl: url, token: token, client: server.client),
      );
      addTearDown(b.dispose);
      final library = LibraryController(b);
      addTearDown(library.dispose);
      final listedWithoutPages = <String>[];
      var announced = 0;
      b.sync.remoteChanges.listen((c) {
        if (!c.notebooks) return;
        announced++;
        library.reload();
        // What the user could open (an editor adds a page to one without).
        for (final n in library.visibleNotebooks) {
          if (b.pages.pagesOf(n.id).isEmpty) listedWithoutPages.add(n.title);
        }
      });
      b.sync.configure(url: 'http://sync.test', token: FakeServer.token);
      await b.sync.syncNow();
      await pumpEventQueue();
      expect(announced, greaterThan(1), reason: 'announced mid-pull too');
      expect(listedWithoutPages, isEmpty);
      expect(library.visibleNotebooks, hasLength(3));
      for (final n in all) {
        expect(b.pages.pagesOf(n.id), hasLength(4));
      }
    });

    test('concurrent syncNow calls coalesce into one follow-up run', () async {
      final server = FakeServer();
      final a = AppServices.create(AppDatabase.inMemory());
      final controller = SyncController(
        engine: a.sync.engine,
        settings: a.settings,
        tokens: a.sync.tokens,
        apiFactory: (url, token) => SyncApi(baseUrl: url, token: token, client: server.client),
      );
      controller.configure(url: 'http://sync.test', token: FakeServer.token);
      final runs = [controller.syncNow(), controller.syncNow(), controller.syncNow()];
      await Future.wait(runs);
      expect(server.pulls, 2);
      expect(controller.state, SyncState.idle);
      controller.dispose();
    });

    test(
      'a failure while reporting a failure still ends in an error, and runs the follow-up',
      () async {
        final server = FakeServer();
        final a = AppServices.create(AppDatabase.inMemory());
        var runs = 0;
        final controller = SyncController(
          engine: a.sync.engine,
          settings: a.settings,
          tokens: a.sync.tokens,
          apiFactory: (url, token) {
            runs++;
            return SyncApi(baseUrl: url, token: token, client: server.client);
          },
        );
        controller.configure(url: 'http://sync.test', token: FakeServer.token);
        // A broken database: the sync fails, and so does reading the blobs
        // too large to upload while reporting it.
        a.database.db.execute('DROP TABLE blobs');
        await Future.wait([controller.syncNow(), controller.syncNow()]);
        expect(runs, 2);
        expect(controller.state, SyncState.error);
        controller.dispose();
      },
    );

    test('disposing during a sync neither throws nor writes', () async {
      final server = FakeServer();
      final a = AppServices.create(AppDatabase.inMemory());
      final controller = SyncController(
        engine: a.sync.engine,
        settings: a.settings,
        tokens: a.sync.tokens,
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

    test('switching servers aborts a request stuck on the old one', () async {
      final stuck = _StuckClient();
      final server = FakeServer();
      final a = AppServices.create(AppDatabase.inMemory());
      final controller = SyncController(
        engine: a.sync.engine,
        settings: a.settings,
        tokens: a.sync.tokens,
        apiFactory: (url, token) => SyncApi(
          baseUrl: url,
          token: token,
          client: url == 'http://old.test' ? stuck : server.client,
        ),
      );
      controller.configure(url: 'http://old.test', token: FakeServer.token);
      final old = controller.syncNow();
      await pumpEventQueue();
      expect(stuck.waiting, isTrue, reason: 'e.g. a long upload or a dead connection');

      controller.configure(url: 'http://new.test', token: FakeServer.token);
      // Waited for the old request's timeout (30 s; 30 min for a blob).
      await controller.syncNow().timeout(const Duration(seconds: 10));
      await old;
      expect(server.pulls, 1);
      expect(controller.state, SyncState.idle);
      controller.dispose();
    });

    test('unexpected errors end in the error state', () async {
      final a = AppServices.create(AppDatabase.inMemory());
      final controller = SyncController(
        engine: a.sync.engine,
        settings: a.settings,
        tokens: a.sync.tokens,
        apiFactory: (url, token) => throw StateError('boom'),
      );
      controller.configure(url: 'http://sync.test', token: FakeServer.token);
      await controller.syncNow();
      expect(controller.state, SyncState.error);
      expect(controller.lastError, isNot(contains('boom')));
      expect(controller.lastErrorDetails, contains('boom'));
      controller.dispose();
    });
  });
}

/// An HTTP client whose requests hang until it is closed (as `IOClient`'s
/// close aborts requests in flight).
class _StuckClient extends http.BaseClient {
  final _closed = Completer<void>();
  bool waiting = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    waiting = true;
    await _closed.future;
    throw http.ClientException('Connection closed', request.url);
  }

  @override
  void close() {
    if (!_closed.isCompleted) _closed.complete();
  }
}
