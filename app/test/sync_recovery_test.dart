import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/recording.dart';
import 'package:len/sync/pull_applier.dart';
import 'package:len/sync/sync_api.dart';

import 'support/fake_server.dart';
import 'support/two_devices.dart';

// Sync under failures: servers that lose history, requests that fail half
// way, edits made while a sync is running.

/// An API to [server] whose requests first pass [hook], which may change
/// local data or throw (a dropped connection); [hook] returning a response
/// answers instead of the server.
SyncApi _hookedApi(FakeServer server, Future<http.Response?> Function(http.Request request) hook) =>
    SyncApi(
      baseUrl: 'http://sync.test',
      token: FakeServer.token,
      client: MockClient((request) async {
        if (await hook(request) case final answer?) return answer;
        final copy = http.Request(request.method, request.url)
          ..headers.addAll(request.headers)
          ..bodyBytes = request.bodyBytes;
        return http.Response.fromStream(await server.client.send(copy));
      }),
    );

Notebook _notebook(TestDevice d, String title) => d.s.notebooks.create(
  title: title,
  kind: NotebookKind.canvas,
  paper: PaperStyle.blank,
  coverColor: 0,
);

List<String> _titles(TestDevice d) => [for (final n in d.s.notebooks.list()) n.title]..sort();

void main() {
  group('a server that lost history', () {
    test('restored from a backup: every device uploads again, nothing is lost', () async {
      final (a, b) = twoDevices();
      final server = a.server;
      _notebook(a, 'Old');
      await send(a, b);
      final backup = server.stored('notebooks', a.s.notebooks.list().single.id)!['seq']! as int;

      // After the backup: A writes, B pulls it, then the server is restored.
      final lost = _notebook(a, 'New on A');
      await send(a, b);
      server.restoreBackup(backup);
      expect(server.stored('notebooks', lost.id), isNull);

      // B syncs first (it saw seq 2, which the server no longer has).
      _notebook(b, 'New on B');
      await b.sync();
      expect(b.s.settings.syncServerId, server.serverId);
      expect(b.s.sync.engine.takeResync(), contains('lost recent changes'));
      expect(b.s.sync.engine.takeResync(), isNull, reason: 'said once');
      await a.sync();
      await b.sync();

      for (final d in [a, b]) {
        expect(_titles(d), ['New on A', 'New on B', 'Old']);
        expect(d.dirty, isEmpty);
      }
      // The server has everything again, so a new device gets it all.
      final c = TestDevice(server, a.time, 'c');
      await c.sync();
      expect(_titles(c), ['New on A', 'New on B', 'Old']);
    });

    test('replaced by an empty server at the same address', () async {
      final (a, b) = twoDevices();
      _notebook(a, 'Kept');
      await send(a, b);

      a.server
        ..restoreBackup(0)
        ..serverId = 'fresh';
      await a.sync();
      expect(a.server.stored('notebooks', a.s.notebooks.list().single.id), isNotNull);
      await b.sync();
      expect(_titles(b), ['Kept']);
      expect(b.dirty, isEmpty);
    });
  });

  group('partial failures', () {
    test('a push failing half way is completed next time, without duplicates', () async {
      final (a, _) = twoDevices();
      a.s.strokes.save([for (var i = 0; i < 600; i++) bigStroke('s$i', 'canvas', 1000)]);
      var pushes = 0;
      final flaky = _hookedApi(a.server, (r) async {
        if (r.url.path == '/v1/push' && ++pushes == 2) throw http.ClientException('reset');
        return null;
      });
      await expectLater(a.s.sync.engine.sync(flaky), throwsA(isA<SyncException>()));
      final first = a.server.pushes.single.count;
      expect(first, inInclusiveRange(1, 599));
      expect(a.dirty, hasLength(600), reason: 'nothing is clean before the server confirms');

      await a.sync();
      expect(a.dirty, isEmpty);
      for (var i = 0; i < 600; i++) {
        expect(a.server.stored('strokes', 's$i'), isNotNull);
      }
    });

    test('a record the server rejects is skipped, the rest is pushed', () async {
      final (a, b) = twoDevices();
      a.s.strokes.save([for (var i = 0; i < 5; i++) bigStroke('s$i', 'canvas', 4)]);
      a.server.invalidRecords.addAll(['s1', 's3']);
      await a.sync();
      expect(a.dirty.map((r) => r.id), ['s1', 's3'], reason: 'kept to retry');
      for (final id in ['s0', 's2', 's4']) {
        expect(a.server.stored('strokes', id), isNotNull);
      }
      await b.sync();
      expect(b.db.select('SELECT COUNT(*) AS n FROM strokes').single['n'], 3);

      // Accepted once the server takes it (e.g. after an update).
      a.server.invalidRecords.clear();
      await a.sync();
      expect(a.dirty, isEmpty);
    });

    test('a proxy with a smaller body limit: pushes split, a record over it is skipped', () async {
      final (a, b) = twoDevices();
      // 20 strokes of ~0.25 MB, one of ~1.6 MB.
      a.s.strokes.save([for (var i = 0; i < 20; i++) bigStroke('s$i', 'canvas', 16000)]);
      a.s.strokes.save([bigStroke('huge', 'canvas', 100000)]);
      const limit = 1024 * 1024; // nginx's default client_max_body_size.
      final proxied = _hookedApi(a.server, (r) async {
        if (r.url.path != '/v1/push' || r.bodyBytes.length <= limit) return null;
        return http.Response('<html>413 Request Entity Too Large</html>', 413);
      });
      await a.s.sync.engine.sync(proxied);
      expect(a.dirty.map((r) => r.id), ['huge'], reason: 'kept, as for the server limit');
      for (var i = 0; i < 20; i++) {
        expect(a.server.stored('strokes', 's$i'), isNotNull);
      }
      expect(a.server.pushes.every((p) => p.bytes <= limit), isTrue);
      await b.sync();
      expect(b.db.select('SELECT COUNT(*) AS n FROM strokes').single['n'], 20);
    });

    test('a 400 without an index still fails the sync', () async {
      final (a, _) = twoDevices();
      a.s.strokes.save([bigStroke('s', 'canvas', 4)]);
      final api = _hookedApi(a.server, (r) async {
        if (r.url.path != '/v1/push') return null;
        return http.Response('{"error":"body must be a JSON object"}', 400);
      });
      await expectLater(a.s.sync.engine.sync(api), throwsA(isA<SyncException>()));
      expect(a.dirty, hasLength(1));
    });

    test('a pull failing half way resumes after the last applied page', () async {
      final (a, b) = twoDevices();
      const total = SyncApi.pullLimit + 200;
      a.s.strokes.save([for (var i = 0; i < total; i++) bigStroke('s$i', 'canvas', 4)]);
      await a.sync();
      var pulls = 0;
      final flaky = _hookedApi(a.server, (r) async {
        if (r.url.path == '/v1/pull' && ++pulls == 2) throw http.ClientException('reset');
        return null;
      });
      await expectLater(b.s.sync.engine.sync(flaky), throwsA(isA<SyncException>()));
      expect(b.s.settings.syncLastSeq, SyncApi.pullLimit);
      expect(b.db.select('SELECT COUNT(*) AS n FROM strokes').single['n'], SyncApi.pullLimit);

      final before = a.server.pulls;
      await b.sync();
      expect(a.server.pulls - before, 1, reason: 'resumes, not from the start');
      expect(b.db.select('SELECT COUNT(*) AS n FROM strokes').single['n'], total);
    });

    test('what a failed pull applied is still announced by the next sync', () async {
      final (a, b) = twoDevices();
      final nb = _notebook(a, 'Big');
      const total = SyncApi.pullLimit + 200;
      a.s.strokes.save([for (var i = 0; i < total; i++) bigStroke('s$i', nb.id, 4)]);
      await a.sync();
      var pulls = 0;
      final flaky = _hookedApi(a.server, (r) async {
        if (r.url.path == '/v1/pull' && ++pulls == 2) throw http.ClientException('reset');
        return null;
      });
      // The first page (the notebook and most strokes) is applied, then the
      // connection drops.
      await expectLater(b.s.sync.engine.sync(flaky), throwsA(isA<SyncException>()));
      expect(_titles(b), ['Big']);

      final changes = await b.sync();
      expect(changes.notebooks, isTrue, reason: 'the library must learn about the notebook');
      expect(changes.strokeSurfaces, {nb.id});
      expect((await b.sync()).isEmpty, isTrue, reason: 'announced once');
    });

    test('a database error half way through a page: what it applied is still announced', () async {
      final (a, b) = twoDevices();
      final notebooks = [for (var n = 0; n < 4; n++) _notebook(a, 'N$n')];
      for (final nb in notebooks) {
        a.s.strokes.save([for (var i = 0; i < 100; i++) bigStroke('${nb.id}-$i', nb.id, 4)]);
      }
      await a.sync();
      // Many slices (a few records each, whatever the machine's speed), the
      // last record failing.
      PullApplier.debugSliceRecords = 10;
      addTearDown(() => PullApplier.debugSliceRecords = null);
      final last = '${notebooks.last.id}-99';
      b.db.execute('''
        CREATE TRIGGER test_fail BEFORE INSERT ON strokes WHEN NEW.id = '$last' BEGIN
          SELECT RAISE(ABORT, 'disk on fire');
        END''');
      await expectLater(b.s.sync.engine.sync(apiFor(a.server)), throwsA(isA<Exception>()));
      final applied = {
        for (final r in b.db.select('SELECT DISTINCT surface_id FROM strokes')) r['surface_id'],
      };
      expect(applied, isNotEmpty, reason: 'slices before the failing one are in');
      b.db.execute('DROP TRIGGER test_fail');

      final changes = await b.sync();
      expect(changes.notebooks, isTrue, reason: 'the library must learn about the notebooks');
      expect(changes.strokeSurfaces, {for (final nb in notebooks) nb.id});
    });

    test('a page is applied in slices; one cut short is pulled again', () async {
      final (a, b) = twoDevices();
      const total = SyncApi.pullLimit;
      a.s.strokes.save([for (var i = 0; i < total; i++) bigStroke('s$i', 'canvas', 4)]);
      await a.sync();
      // Cancelled as soon as the first slice is in.
      int count() => b.db.select('SELECT COUNT(*) AS n FROM strokes').single['n'] as int;
      await b.s.sync.engine.sync(apiFor(a.server), isCancelled: () => count() > 0);
      expect(count(), inInclusiveRange(1, total - 1));
      expect(b.s.settings.syncLastSeq, 0, reason: 'the feed position waits for the page');

      await b.sync();
      expect(b.db.select('SELECT COUNT(*) AS n FROM strokes').single['n'], total);
      expect(b.dirty, isEmpty, reason: 'records applied twice change nothing');
    });
  });

  group('edits during a sync', () {
    test('a row edited while its push is in flight stays dirty', () async {
      final (a, _) = twoDevices();
      final nb = _notebook(a, 'Before');
      final api = _hookedApi(a.server, (r) async {
        if (r.url.path == '/v1/push') {
          a.s.notebooks.update(a.s.notebooks.get(nb.id)!.copyWith(title: 'During'));
        }
        return null;
      });
      await a.s.sync.engine.sync(api);
      expect(a.dirty.single.id, nb.id);
      await a.sync();
      expect((a.server.stored('notebooks', nb.id)!['data']! as Map)['title'], 'During');
    });

    test('a record written during the push does not overtake its blob', () async {
      final (a, _) = twoDevices();
      final nb = _notebook(a, 'N');
      Recording? recording;
      final api = _hookedApi(a.server, (r) async {
        // While notebooks are pushed, a recording is saved: its blob is
        // stored after the upload phase, its record before recordings push.
        if (r.url.path == '/v1/push' && recording == null) {
          final sha = await a.s.blobs.putBytes(Uint8List.fromList([1, 2, 3]), mime: 'audio/mp4');
          recording = a.s.recordings.save(
            notebookId: nb.id,
            parts: [RecordingPart(sha, 1000)],
            mime: 'audio/mp4',
            title: 'R',
            segments: [const RecordingSegment(1, 1000)],
          );
        }
        return null;
      });
      await a.s.sync.engine.sync(api);
      expect(a.server.stored('recordings', recording!.id), isNull);
      expect(a.dirty.map((r) => r.id), contains(recording!.id));

      await a.sync();
      expect(a.server.blobs, hasLength(1));
      expect(a.server.stored('recordings', recording!.id), isNotNull);
      final order = a.server.log.where((l) => l != 'HEAD blob').toList();
      expect(order.lastIndexOf('PUT blob'), lessThan(order.lastIndexOf('push')));
    });
  });
}
