import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/sync/server_events.dart';
import 'package:len/sync/sync_api.dart';
import 'package:len_sync_server/len_sync_server.dart' as server;

import 'support/real_server.dart';

// The pieces of near-live sync (see sync_live_test.dart for them together).

Stream<List<int>> _chunks(String text, int size) async* {
  final bytes = utf8.encode(text);
  for (var i = 0; i < bytes.length; i += size) {
    yield bytes.sublist(i, math.min(i + size, bytes.length));
  }
}

/// A client of [server] that lets [before] run before each request.
class _Hooked extends http.BaseClient {
  _Hooked(this.server, this.before);

  final RealServer server;
  final void Function(http.BaseRequest request) before;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    before(request);
    return server.handle(request);
  }
}

void main() {
  group('parseServerEvents', () {
    test('events, heartbeats and noise, however the bytes are split', () async {
      const body =
          ': hello\n\n'
          'data: {"seq":3,"serverId":"s1"}\n\n'
          'retry: 1000\r\nid: 7\r\ndata:{"seq":4,\r\ndata: "serverId":"s1"}\r\n\r\n'
          'event: other\ndata: not json\n\n'
          'data: {"seq":-1,"serverId":"s1"}\n\n'
          ': ping\r\r'
          'data: {"seq":5,"serverId":"s2"}\n\n'
          'data: {"seq":6,"serverId":"s2"}'; // cut off: no event
      for (final size in [1, 3, 7, 1000]) {
        final events = await parseServerEvents(_chunks(body, size)).toList();
        expect(events, [
          null,
          (seq: 3, serverId: 's1'),
          (seq: 4, serverId: 's1'),
          null,
          null,
          null,
          (seq: 5, serverId: 's2'),
        ], reason: 'chunks of $size');
      }
    });

    test('cancelling lets go of the connection at once', () async {
      var cancelled = false;
      final source = Stream<List<int>>.periodic(
        const Duration(hours: 1),
        (_) => utf8.encode(': ping\n\n'),
      ).asBroadcastStream(onCancel: (_) => cancelled = true);
      final subscription = parseServerEvents(source).listen((_) {});
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      expect(cancelled, isTrue);
    });
  });

  group('DirtyWrites', () {
    test('counts rows local writes mark for upload, not pulled ones', () async {
      final real = RealServer();
      addTearDown(real.dispose);
      AppServices device() {
        final s = AppServices.create(AppDatabase.inMemory());
        addTearDown(s.dispose);
        return s;
      }

      final a = device();
      final b = device();
      SyncApi api() =>
          SyncApi(baseUrl: 'http://sync.test', token: RealServer.token, client: real.client);
      final writes = b.sync.engine.dirtyWrites;
      final folder = b.folders.create(name: 'Mine', color: 1);
      expect(writes.count, 1);
      b.folders.update(folder.copyWith(name: 'Renamed'));
      expect(writes.count, 2);
      // The first sync with a server marks every row for upload.
      await b.sync.engine.sync(api());
      expect(writes.count, 3);

      a.folders.create(name: 'Theirs', color: 2);
      a.folders.create(name: 'Theirs too', color: 3);
      await a.sync.engine.sync(api());
      await b.sync.engine.sync(api());
      // Pulled and marked clean: nothing counted.
      expect(b.folders.list(), hasLength(3));
      expect(writes.count, 3);
      expect(b.sync.engine.hasDirtyRows(), isFalse);

      b.folders.delete(folder.id);
      expect(writes.count, 4);
      expect(b.sync.engine.hasDirtyRows(), isTrue);
    });
  });

  group('knownSeq', () {
    late RealServer real;
    late AppServices a;

    setUp(() {
      real = RealServer();
      a = AppServices.create(AppDatabase.inMemory());
      addTearDown(() {
        a.dispose();
        real.dispose();
      });
    });

    server.SyncRecord other(String id) => server.SyncRecord.fromJson({
      'collection': 'folders',
      'id': id,
      'updatedAt': 1,
      'deviceId': 'zz',
      'deleted': false,
      'data': {'name': id, 'parentId': null, 'color': 0, 'createdAt': 1},
    });

    test('takes in what this device pushed after the pull', () async {
      final folder = a.folders.create(name: 'F', color: 1);
      await a.sync.engine.sync(
        SyncApi(baseUrl: 'http://sync.test', token: RealServer.token, client: real.client),
      );
      expect(a.sync.engine.knownSeq, real.store.currentSeq());
      // A deletion is pushed after the pull: its seq is this device's own.
      a.folders.delete(folder.id);
      await a.sync.engine.sync(
        SyncApi(baseUrl: 'http://sync.test', token: RealServer.token, client: real.client),
      );
      final seq = real.store.currentSeq();
      expect(a.settings.syncLastSeq, seq - 1);
      expect(a.sync.engine.knownSeq, seq);
    });

    test('not when another device pushed in between', () async {
      final folder = a.folders.create(name: 'F', color: 1);
      var sneak = false;
      final api = SyncApi(
        baseUrl: 'http://sync.test',
        token: RealServer.token,
        client: _Hooked(real, (request) {
          // Another device's push lands right before this one's.
          if (sneak && request.url.path == '/v1/push') {
            real.store.push([other('x${real.store.currentSeq()}')]);
          }
        }),
      );
      await a.sync.engine.sync(api);
      a.folders.delete(folder.id);
      sneak = true;
      await a.sync.engine.sync(api);
      final seq = real.store.currentSeq();
      // This device pulled up to the other's change but pushed after it:
      // the other device's change came first, so the deletion's seq is not
      // known to follow on from what this device has.
      expect(a.settings.syncLastSeq, lessThan(seq));
      expect(a.sync.engine.knownSeq, lessThan(seq));
    });
  });
}
