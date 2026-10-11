import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/recording.dart';
import 'package:len/features/settings/sync_settings.dart';
import 'package:len/sync/sync_api.dart';
import 'package:len/sync/sync_controller.dart';
import 'package:len/sync/sync_engine.dart';
import 'package:len/ui/app_theme.dart';
import 'package:len/ui/sync_status_button.dart';

import 'support/fake_server.dart';

AppServices _device(FakeServer server) {
  final s = AppServices.create(
    AppDatabase.inMemory(),
    syncApiFactory: (url, token) => SyncApi(baseUrl: url, token: token, client: server.client),
  );
  s.sync.configure(url: 'http://sync.test', token: FakeServer.token);
  return s;
}

/// Stores [size] bytes as a blob and a recording referencing it.
Future<({String sha, Recording recording})> _recording(AppServices s, int size, int seed) async {
  final sha = await s.blobs.putBytes(
    Uint8List.fromList(List.filled(size, seed)),
    mime: 'audio/mp4',
  );
  final notebook = s.notebooks.create(
    title: 'N$seed',
    kind: NotebookKind.paged,
    paper: PaperStyle.blank,
    coverColor: 0,
  );
  final recording = s.recordings.create(
    notebookId: notebook.id,
    blob: sha,
    mime: 'audio/mp4',
    title: 'R$seed',
    segments: [RecordingSegment(1, 1000)],
  );
  return (sha: sha, recording: recording);
}

void main() {
  late FakeServer server;
  late AppServices a;

  setUp(() {
    server = FakeServer();
    a = _device(server);
  });
  tearDown(() => a.dispose());

  bool pushed(Recording r) => server.stored('recordings', r.id) != null;

  group('blobs too large for the server', () {
    test('skipped up front when the server advertises its limit; the rest syncs', () async {
      server.maxBlobBytes = 100;
      final big = await _recording(a, 500, 1);
      final small = await _recording(a, 50, 2);

      await a.sync.syncNow();
      expect(a.sync.state, SyncState.idle);
      expect(a.sync.lastError, isNull);
      expect(server.putAttempts, [small.sha]); // The big one is never sent.
      expect(pushed(big.recording), isTrue); // Its record syncs without it.
      expect(pushed(small.recording), isTrue);
      expect(a.sync.tooLargeFiles.map((f) => f.sha), [big.sha]);
      expect(a.sync.tooLargeSummary, '1 file too large to sync');
      expect(a.sync.serverMaxBlobBytes, 100);

      // Later syncs do not try again.
      await a.sync.syncNow();
      expect(server.putAttempts, [small.sha]);
      expect(a.blobs.pendingUploads(), isEmpty);
    });

    test('a 413 marks the blob too large instead of failing every sync', () async {
      server.rejectBlobsAbove = 100; // e.g. a proxy; the server says nothing.
      final big = await _recording(a, 500, 1);
      final small = await _recording(a, 50, 2);

      await a.sync.syncNow();
      expect(a.sync.state, SyncState.idle);
      expect(server.putAttempts, [big.sha, small.sha]);
      expect(server.blobs.keys, [small.sha]);
      expect(pushed(big.recording), isTrue);
      expect(a.sync.tooLargeFiles.single.size, 500);

      await a.sync.syncNow();
      expect(server.putAttempts, hasLength(2));
    });

    test('uploaded once the server limit is raised', () async {
      server.maxBlobBytes = 100;
      final big = await _recording(a, 500, 1);
      await a.sync.syncNow();
      expect(a.sync.tooLargeFiles, hasLength(1));

      server.maxBlobBytes = 1000;
      await a.sync.syncNow();
      expect(server.blobs.keys, [big.sha]);
      expect(a.sync.tooLargeFiles, isEmpty);
      expect(a.sync.tooLargeSummary, isNull);
    });

    test('a proxy limit below the advertised one does not cause retries', () async {
      server
        ..maxBlobBytes = 1000
        ..rejectBlobsAbove = 100;
      await _recording(a, 500, 1);
      await a.sync.syncNow();
      await a.sync.syncNow();
      expect(server.putAttempts, hasLength(1));
      expect(a.sync.tooLargeFiles, hasLength(1));

      // "Retry" in Settings tries again.
      server.rejectBlobsAbove = null;
      await a.sync.retryTooLargeFiles();
      expect(server.putAttempts, hasLength(2));
      expect(a.sync.tooLargeFiles, isEmpty);
    });

    test('switching servers forgets "too large"', () async {
      server.maxBlobBytes = 100;
      await _recording(a, 500, 1);
      await a.sync.syncNow();
      expect(a.sync.tooLargeFiles, hasLength(1));

      a.sync.configure(url: 'http://other.test', token: FakeServer.token);
      expect(a.sync.tooLargeFiles, isEmpty);
      expect(a.blobs.pendingUploads(), hasLength(1));
    });
  });

  group('transient blob failures', () {
    test('do not block other blobs; records wait for their blob; retried', () async {
      final failing = await _recording(a, 50, 1);
      final fine = await _recording(a, 50, 2);
      server.failingPuts.add(failing.sha);

      await a.sync.syncNow();
      expect(server.blobs.keys, [fine.sha]);
      expect(pushed(fine.recording), isTrue);
      expect(pushed(failing.recording), isFalse); // Held back: blob not there yet.
      expect(server.stored('notebooks', failing.recording.notebookId), isNotNull);
      expect(a.sync.state, SyncState.error);
      expect(a.sync.lastError, contains('1 file could not be uploaded'));
      expect(a.sync.lastError, contains('disk full'));
      expect(a.sync.tooLargeFiles, isEmpty);

      server.failingPuts.clear();
      await a.sync.syncNow();
      expect(a.sync.state, SyncState.idle);
      expect(server.blobs.keys, containsAll([failing.sha, fine.sha]));
      expect(pushed(failing.recording), isTrue);
    });

    test('a blob that keeps failing stops holding back its records', () async {
      final failing = await _recording(a, 50, 1);
      server.failingPuts.add(failing.sha);
      for (var i = 1; i < SyncEngine.maxHoldBackAttempts; i++) {
        await a.sync.syncNow();
        expect(pushed(failing.recording), isFalse, reason: 'sync $i');
      }
      await a.sync.syncNow();
      expect(pushed(failing.recording), isTrue);
      expect(a.sync.state, SyncState.error); // Still retried and reported.
      expect(a.blobs.pendingUploads(), [failing.sha]);
    });

    test('an unreachable server fails the sync before anything is pushed', () async {
      final b = AppServices.create(
        AppDatabase.inMemory(),
        syncApiFactory: (url, token) => SyncApi(
          baseUrl: url,
          token: token,
          client: MockClient((request) async {
            if (request.method == 'HEAD') throw http.ClientException('connection refused');
            final copy = http.Request(request.method, request.url)
              ..headers.addAll(request.headers)
              ..bodyBytes = request.bodyBytes;
            return http.Response.fromStream(await server.client.send(copy));
          }),
        ),
      );
      addTearDown(b.dispose);
      b.sync.configure(url: 'http://sync.test', token: FakeServer.token);
      final r = await _recording(b, 50, 1);
      await b.sync.syncNow();
      expect(b.sync.state, SyncState.error);
      expect(b.sync.lastError, contains('Cannot reach'));
      expect(pushed(r.recording), isFalse);
      expect(server.log.where((l) => l == 'push'), isEmpty);
    });
  });

  group('SyncApi', () {
    SyncApi api(http.Response Function(http.Request) handle) => SyncApi(
      baseUrl: 'http://sync.test',
      token: FakeServer.token,
      client: MockClient((r) async => handle(r)),
    );

    test('serverInfo reads the limit and tolerates old servers and proxies', () async {
      var info = await api(
        (_) => http.Response('{"status":"ok","maxBlobBytes":42,"blobsCollectedAt":7,"x":1}', 200),
      ).serverInfo();
      expect((info.maxBlobBytes, info.blobsCollectedAt), (42, 7));
      info = await api((_) => http.Response('{"status":"ok","blobs":true}', 200)).serverInfo();
      expect((info.maxBlobBytes, info.blobsCollectedAt), (null, null));
      info = await api((_) => http.Response('<html>bad gateway</html>', 502)).serverInfo();
      expect(info.maxBlobBytes, isNull);
      info = await api((_) => http.Response('{"maxBlobBytes":"big"}', 200)).serverInfo();
      expect(info.maxBlobBytes, isNull);
      await expectLater(
        api((_) => throw http.ClientException('offline')).serverInfo(),
        throwsA(isA<SyncException>().having((e) => e.kind, 'kind', SyncFailure.network)),
      );
    });

    test('putBlob reports 413 as too large, 500 as a server error', () async {
      for (final (status, kind) in [(413, SyncFailure.tooLarge), (500, SyncFailure.server)]) {
        await expectLater(
          api((_) => http.Response('{"error":"no"}', status))
              .putBlob('a' * 64, Stream.value([1, 2, 3]), length: 3),
          throwsA(isA<SyncException>().having((e) => e.kind, 'kind', kind)),
        );
      }
    });
  });

  test('unreferenced blobs are not uploaded', () async {
    await a.blobs.putBytes(Uint8List.fromList(utf8.encode('deleted image')), mime: 'image/png');
    await a.sync.syncNow();
    expect(server.putAttempts, isEmpty);
    expect(a.sync.state, SyncState.idle);
  });

  test('after server garbage collection, uploads are re-checked', () async {
    final r = await _recording(a, 50, 1);
    await a.sync.syncNow();
    expect(server.blobs.keys, [r.sha]);

    // The server lost the blob (e.g. collected while this device was away).
    server.blobs.clear();
    await a.sync.syncNow();
    expect(server.blobs, isEmpty); // Uploaded marks are trusted...

    server.blobsCollectedAt = 1234;
    await a.sync.syncNow();
    expect(server.blobs.keys, [r.sha]); // ...until the server reports a collection.
    expect(a.settings.syncBlobsCollectedAt, 1234);

    server.log.clear();
    await a.sync.syncNow();
    expect(server.log.where((l) => l.endsWith('blob')), isEmpty);
  });

  group('status UI', () {
    Future<void> pump(WidgetTester tester, Widget child) async {
      tester.view
        ..physicalSize = const Size(800, 1400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(() => tester.pumpWidget(const SizedBox()));
      await tester.pumpWidget(
        AppScope(
          services: a,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(body: SingleChildScrollView(child: child)),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('Settings → Sync and the status button show files too large', (tester) async {
      server.maxBlobBytes = 100;
      await tester.runAsync(() async {
        await _recording(a, 500, 1);
        await a.sync.syncNow();
      });
      await pump(
        tester,
        Column(
          children: [
            const SyncSettings(),
            SyncStatusButton(sync: a.sync, onConfigure: () {}),
          ],
        ),
      );
      expect(find.text('1 file too large to sync.'), findsOneWidget);
      expect(find.textContaining('the server accepts up to 100 bytes'), findsOneWidget);
      expect(find.byTooltip('Synced — tap to sync now\n1 file too large to sync'), findsOneWidget);

      server.maxBlobBytes = null;
      await tester.runAsync(() => a.sync.retryTooLargeFiles());
      await tester.pump();
      expect(find.text('1 file too large to sync.'), findsNothing);
      expect(server.blobs, hasLength(1));
    });
  });
}
