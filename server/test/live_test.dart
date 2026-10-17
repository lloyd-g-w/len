import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:len_sync_server/len_sync_server.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

const token = 'test-token-0123456789abcdef';

/// A live connection's client end (dart:io WebSocket), its messages queued.
class Client {
  Client._(this.ws) {
    _sub = ws.listen(
      (raw) {
        final m = jsonDecode(raw as String) as Map<String, Object?>;
        if (m['type'] == 'heartbeat') {
          heartbeats++;
          return;
        }
        if (_waiting.isNotEmpty) {
          _waiting.removeFirst().complete(m);
        } else {
          _queue.add(m);
        }
      },
      onDone: () {
        done.complete(ws.closeCode);
        for (final w in _waiting) {
          w.completeError(StateError('closed (${ws.closeCode})'));
        }
        _waiting.clear();
      },
    );
  }

  static Future<Client> connect(int port, {String? auth = token, String? ticket}) async {
    final ws = await WebSocket.connect(
      'ws://127.0.0.1:$port/v1/live${ticket == null ? '' : '?ticket=$ticket'}',
      headers: {if (auth != null) 'Authorization': 'Bearer $auth'},
    );
    return Client._(ws);
  }

  final WebSocket ws;
  late final StreamSubscription<Object?> _sub;
  final _queue = Queue<Map<String, Object?>>();
  final _waiting = Queue<Completer<Map<String, Object?>>>();
  final done = Completer<int?>();
  int heartbeats = 0;

  /// The next message (heartbeats aside).
  Future<Map<String, Object?>> next({Duration timeout = const Duration(seconds: 5)}) {
    if (_queue.isNotEmpty) return Future.value(_queue.removeFirst());
    final c = Completer<Map<String, Object?>>();
    _waiting.add(c);
    return c.future.timeout(
      timeout,
      onTimeout: () {
        _waiting.remove(c);
        throw TimeoutException('no message', timeout);
      },
    );
  }

  /// The next message, which must be of [type].
  Future<Map<String, Object?>> expectNext(String type) async {
    final m = await next();
    expect(m['type'], type, reason: '$m');
    return m;
  }

  /// Nothing else arrives before a `pong` (round trip through the server).
  Future<void> expectNothingMore() async {
    send({'type': 'ping', 'id': 'sync'});
    expect(await next(), {'type': 'pong', 'id': 'sync'});
  }

  void send(Map<String, Object?> message) => ws.add(jsonEncode(message));

  void pause() => _sub.pause();
  void resume() => _sub.resume();

  Future<void> close() async {
    await ws.close();
    await _sub.cancel();
  }
}

Map<String, Object?> record(String id, {int updatedAt = 1000, String device = 'dev-1'}) => {
  'collection': 'notebooks',
  'id': id,
  'updatedAt': updatedAt,
  'deviceId': device,
  'deleted': false,
  'data': {'title': id},
};

void main() {
  late RecordStore store;
  late Directory blobDir;
  late LiveHub hub;
  late LiveTickets tickets;
  late HttpServer server;
  late int port;
  final clients = <Client>[];
  var now = DateTime(2026);

  Future<void> serve({LiveLimits limits = const LiveLimits()}) async {
    hub = LiveHub(limits: limits);
    tickets = LiveTickets(now: () => now);
    server = await shelf_io.serve(
      buildHandler(
        store: store,
        blobs: BlobStore.open(blobDir.path),
        token: token,
        live: hub,
        tickets: tickets,
      ),
      InternetAddress.loopbackIPv4,
      0,
    );
    port = server.port;
  }

  Future<Client> connect({String? auth = token, String? ticket}) async {
    final c = await Client.connect(port, auth: auth, ticket: ticket);
    clients.add(c);
    return c;
  }

  /// A connected client past its `hello`.
  Future<Client> ready() async {
    final c = await connect();
    await c.expectNext('hello');
    return c;
  }

  /// An HTTP request to the server: its status and body.
  Future<({int status, String body})> request(
    String method,
    String path, {
    Object? body,
    bool auth = true,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));
      if (auth) request.headers.set('authorization', 'Bearer $token');
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close();
      return (status: response.statusCode, body: await response.transform(utf8.decoder).join());
    } finally {
      client.close();
    }
  }

  Future<({int status, String body})> post(String path, Object body) =>
      request('POST', path, body: body);

  setUp(() async {
    store = RecordStore.inMemory();
    blobDir = Directory.systemTemp.createTempSync('len_live_test_');
    now = DateTime(2026);
    await serve();
  });

  tearDown(() async {
    for (final c in clients) {
      await c.close();
    }
    clients.clear();
    await hub.close();
    await server.close(force: true);
    store.close();
    blobDir.deleteSync(recursive: true);
  });

  group('auth', () {
    test('the bearer token in a header opens a connection, greeted with hello', () async {
      store.push([SyncRecord.fromJson(record('a'))]);
      final c = await connect();
      final hello = await c.expectNext('hello');
      expect(hello['serverId'], store.serverId);
      expect(hello['seq'], 1);
      expect(hello['protocol'], 1);
      expect(hello['connection'], isA<String>());
      expect(hub.connections, 1);
    });

    test('no token, a wrong one or none at all are refused', () async {
      await expectLater(connect(auth: null), throwsA(isA<WebSocketException>()));
      await expectLater(
        connect(auth: 'wrong-token-0000000000'),
        throwsA(isA<WebSocketException>()),
      );
      expect(hub.connections, 0);
    });

    test('a ticket opens one connection, once, while it is fresh', () async {
      final response = await post('/v1/live/ticket', {});
      expect(response.status, 200);
      final body = jsonDecode(response.body) as Map<String, Object?>;
      expect(body['expiresIn'], 30);
      final ticket = body['ticket'] as String;
      final c = await connect(auth: null, ticket: ticket);
      await c.expectNext('hello');
      await expectLater(connect(auth: null, ticket: ticket), throwsA(isA<WebSocketException>()));

      final stale = tickets.issue();
      now = now.add(const Duration(seconds: 31));
      await expectLater(connect(auth: null, ticket: stale), throwsA(isA<WebSocketException>()));
    });

    test('tickets need the token', () async {
      final response = await request('POST', '/v1/live/ticket', auth: false);
      expect(response.status, 401);
    });

    test('a plain request is answered 426', () async {
      final response = await request('GET', '/v1/live');
      expect(response.status, 426);
    });
  });

  group('push', () {
    test('applies like POST /v1/push and answers with the seqs', () async {
      final c = await ready();
      c.send({
        'type': 'push',
        'id': 1,
        'since': 0,
        'records': [record('a'), record('b')],
      });
      expect(await c.next(), {
        'type': 'pushed',
        'id': 1,
        'applied': 2,
        'ignored': 0,
        'serverSeq': 2,
      });
      c.send({
        'type': 'push',
        'id': 2,
        'since': 2,
        'records': [record('a')],
      });
      expect(await c.next(), {
        'type': 'pushed',
        'id': 2,
        'applied': 0,
        'ignored': 1,
        'serverSeq': 2,
      });
      expect(store.currentSeq(), 2);
    });

    test('an invalid record is refused with its index; nothing is applied', () async {
      final c = await ready();
      c.send({
        'type': 'push',
        'id': 'x',
        'since': 0,
        'records': [
          record('a'),
          {'collection': 'BAD'},
        ],
      });
      final m = await c.expectNext('error');
      expect(m['id'], 'x');
      expect(m['index'], 1);
      expect(m['status'], 400);
      expect(store.currentSeq(), 0);
    });

    test('"current" pushes are stale while the client lacks changes', () async {
      final a = await ready();
      final b = await ready();
      a.send({
        'type': 'push',
        'id': 1,
        'since': 0,
        'records': [record('a')],
      });
      await a.expectNext('pushed');
      await b.expectNext('records');
      b.send({
        'type': 'push',
        'id': 2,
        'since': 0,
        'current': true,
        'records': [record('b')],
      });
      expect(await b.next(), {'type': 'pushed', 'id': 2, 'stale': true, 'serverSeq': 1});
      b.send({
        'type': 'push',
        'id': 3,
        'since': 1,
        'current': true,
        'records': [record('b')],
      });
      expect((await b.expectNext('pushed'))['applied'], 1);
    });

    test('a push beyond the newest seq: 409, and everyone resyncs', () async {
      final a = await ready();
      final b = await ready();
      final serverId = store.serverId;
      a.send({
        'type': 'push',
        'id': 1,
        'since': 5,
        'records': [record('a')],
      });
      // The pusher too: its own reset follows the error.
      await a.expectNext('resync');
      final error = await a.expectNext('error');
      expect(error['status'], 409);
      final resync = await b.expectNext('resync');
      expect(resync['serverId'], isNot(serverId));
      expect(resync['serverId'], store.serverId);
    });
  });

  group('fan-out', () {
    test('records go to every other connection, not the pusher', () async {
      final a = await ready();
      final b = await ready();
      final c = await ready();
      a.send({
        'type': 'push',
        'id': 1,
        'since': 0,
        'records': [record('x'), record('y')],
      });
      await a.expectNext('pushed');
      for (final other in [b, c]) {
        final m = await other.expectNext('records');
        expect(m['prevSeq'], 0);
        expect(m['seq'], 2);
        final records = (m['records'] as List).cast<Map<String, Object?>>();
        expect([for (final r in records) r['id']], ['x', 'y']);
        expect([for (final r in records) r['seq']], [1, 2]);
        expect(records.first['data'], {'title': 'x'});
      }
      await a.expectNothingMore();
    });

    test('pushes over HTTP reach every connection', () async {
      final a = await ready();
      final response = await post('/v1/push', {
        'since': 0,
        'records': [record('h')],
      });
      expect(response.status, 200);
      final m = await a.expectNext('records');
      expect(m['seq'], 1);
    });

    test('nothing stored, nothing sent', () async {
      final a = await ready();
      final b = await ready();
      for (var i = 0; i < 2; i++) {
        a.send({
          'type': 'push',
          'id': i,
          'since': i,
          'records': [record('same')],
        });
        await a.expectNext('pushed');
      }
      await b.expectNext('records');
      await b.expectNothingMore();
    });

    test('in seq order, without gaps, from many pushers', () async {
      final pushers = [for (var i = 0; i < 3; i++) await ready()];
      final watcher = await ready();
      for (var round = 0; round < 10; round++) {
        for (var p = 0; p < pushers.length; p++) {
          pushers[p].send({
            'type': 'push',
            'since': 0,
            'records': [record('r$round-$p', device: 'd$p')],
          });
        }
      }
      var seq = 0;
      while (seq < 30) {
        final m = await watcher.expectNext('records');
        expect(m['prevSeq'], seq);
        seq = m['seq']! as int;
      }
      // Each pusher hears of the others' records only, and in order too.
      for (final p in pushers) {
        var last = 0;
        var heard = 0;
        while (heard < 20) {
          final m = await p.next();
          if (m['type'] != 'records') continue;
          expect(m['prevSeq'] as int, greaterThanOrEqualTo(last));
          last = m['seq']! as int;
          heard++;
        }
      }
    });

    test('records too large for one message are announced as a resync', () async {
      await hub.close();
      await server.close(force: true);
      await serve(limits: const LiveLimits(maxRecordsFrameBytes: 1000));
      final a = await ready();
      final b = await ready();
      a.send({
        'type': 'push',
        'since': 0,
        'records': [
          {
            ...record('big'),
            'data': {'title': 'x' * 2000},
          },
        ],
      });
      final m = await b.expectNext('resync');
      expect(m['seq'], 1);
      expect(m['serverId'], store.serverId);
    });
  });

  group('limits', () {
    test('a client that does not read gets one resync instead of the changes', () async {
      await hub.close();
      await server.close(force: true);
      await serve(limits: const LiveLimits(maxQueuedBytes: 64 * 1024));
      final a = await ready();
      final b = await ready();
      b.pause();
      // Far more than socket buffers hold.
      final big = 'x' * (256 * 1024);
      for (var i = 0; i < 200; i++) {
        a.send({
          'type': 'push',
          'since': 0,
          'records': [
            {
              ...record('n$i', updatedAt: 1000 + i),
              'data': {'title': big},
            },
          ],
        });
        await a.expectNext('pushed');
      }
      expect(hub.connection('c2')!.dropped, greaterThan(0));
      b.resume();
      var records = 0;
      while (true) {
        final m = await b.next();
        if (m['type'] == 'resync') break;
        expect(m['type'], 'records');
        records++;
      }
      expect(records, lessThan(200));
      await b.expectNothingMore();
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('a client that reads nothing for long is dropped', () async {
      await hub.close();
      await server.close(force: true);
      await serve(
        limits: const LiveLimits(maxQueuedBytes: 64 * 1024, stallTimeout: Duration(seconds: 1)),
      );
      final a = await ready();
      final b = await ready();
      b.pause();
      final big = 'x' * (256 * 1024);
      for (var i = 0; i < 100 && hub.connections > 1; i++) {
        a.send({
          'type': 'push',
          'since': 0,
          'records': [
            {
              ...record('n$i', updatedAt: 1000 + i),
              'data': {'title': big},
            },
          ],
        });
        await a.expectNext('pushed');
      }
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (hub.connections > 1 && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(hub.connections, 1);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('connections beyond the limit are refused', () async {
      await hub.close();
      await server.close(force: true);
      await serve(limits: const LiveLimits(maxConnections: 2));
      await ready();
      await ready();
      await expectLater(connect(), throwsA(isA<WebSocketException>()));
    });

    test('a message too big closes the connection (1009)', () async {
      await hub.close();
      await server.close(force: true);
      await serve(limits: const LiveLimits(maxMessageBytes: 1000));
      final a = await ready();
      a.send({'type': 'ping', 'pad': 'x' * 2000});
      expect(await a.done.future.timeout(const Duration(seconds: 5)), 1009);
    });

    test('unknown or malformed messages are answered with an error', () async {
      final a = await ready();
      a.ws.add('not json');
      await a.expectNext('error');
      a.send({'type': 'dance', 'id': 4});
      expect((await a.expectNext('error'))['id'], 4);
      a.send({'type': 'join', 'room': ''});
      await a.expectNext('error');
    });

    test('heartbeats keep the connection talking', () async {
      await hub.close();
      await server.close(force: true);
      await serve(limits: const LiveLimits(heartbeat: Duration(milliseconds: 50)));
      final a = await ready();
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (a.heartbeats < 2 && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(a.heartbeats, greaterThanOrEqualTo(2));
    });

    test('shutting down closes connections as going away (1001)', () async {
      final a = await ready();
      await hub.close();
      expect(await a.done.future.timeout(const Duration(seconds: 5)), 1001);
      await expectLater(connect(), throwsA(isA<WebSocketException>()));
    });
  });

  group('rooms', () {
    Future<Client> member(String room, {String? device, String? name}) async {
      final c = await ready();
      c.send({'type': 'hello', 'deviceId': ?device, 'name': ?name});
      c.send({'type': 'join', 'room': room});
      return c;
    }

    test('presence tells members who is in the room, as they come and go', () async {
      final a = await member('n1', device: 'dev-a', name: 'Tablet');
      var p = await a.expectNext('presence');
      expect(p['room'], 'n1');
      expect(p['members'], [
        {'connection': 'c1', 'deviceId': 'dev-a', 'name': 'Tablet'},
      ]);
      final b = await member('n1', device: 'dev-b');
      p = await a.expectNext('presence');
      expect((p['members'] as List).length, 2);
      expect((await b.expectNext('presence'))['members'], p['members']);
      final c = await member('n2', device: 'dev-c');
      expect((await c.expectNext('presence'))['members'], hasLength(1));
      await b.close();
      p = await a.expectNext('presence');
      expect(p['members'], [
        {'connection': 'c1', 'deviceId': 'dev-a', 'name': 'Tablet'},
      ]);
      a.send({'type': 'leave', 'room': 'n1'});
      await a.expectNothingMore();
      await c.expectNothingMore();
    });

    test('ephemeral messages reach the room\'s other members only', () async {
      final a = await member('n1', device: 'dev-a');
      final b = await member('n1', device: 'dev-b');
      final c = await member('n2', device: 'dev-c');
      await a.expectNext('presence');
      await a.expectNext('presence');
      await b.expectNext('presence');
      await c.expectNext('presence');
      a.send({
        'type': 'ephemeral',
        'room': 'n1',
        'data': {
          'ink': [1, 2, 3],
        },
      });
      expect(await b.next(), {
        'type': 'ephemeral',
        'room': 'n1',
        'from': 'c1',
        'deviceId': 'dev-a',
        'data': {
          'ink': [1, 2, 3],
        },
      });
      await a.expectNothingMore();
      await c.expectNothingMore();
      // Not stored: no seq moved.
      expect(store.currentSeq(), 0);
      // Only to rooms one joined.
      c.send({'type': 'ephemeral', 'room': 'n1', 'data': {}});
      await c.expectNext('error');
      await b.expectNothingMore();
    });

    test('a pointer streamed at 30 a second gets through the default rate whole', () async {
      final a = await member('n1');
      final b = await member('n1');
      await a.expectNext('presence');
      await a.expectNext('presence');
      await b.expectNext('presence');
      // Longer than the burst lasts: 90 messages over 3 s.
      for (var i = 0; i < 90; i++) {
        a.send({
          'type': 'ephemeral',
          'room': 'n1',
          'data': {
            'k': 'pointer',
            'page': 'p1',
            'at': [i, 2.5],
          },
        });
        await Future<void>.delayed(const Duration(milliseconds: 33));
      }
      for (var i = 0; i < 90; i++) {
        final m = await b.expectNext('ephemeral');
        expect((m['data'] as Map)['at'], [i, 2.5]);
      }
      await a.expectNothingMore();
    });

    test('ephemeral messages are limited in size and rate', () async {
      await hub.close();
      await server.close(force: true);
      await serve(
        limits: const LiveLimits(ephemeralBurst: 5, ephemeralPerSecond: 1, maxEphemeralBytes: 1000),
      );
      final a = await member('n1');
      final b = await member('n1');
      await a.expectNext('presence');
      await a.expectNext('presence');
      await b.expectNext('presence');
      a.send({
        'type': 'ephemeral',
        'room': 'n1',
        'data': {'pad': 'x' * 2000},
      });
      await a.expectNext('error');
      for (var i = 0; i < 20; i++) {
        a.send({
          'type': 'ephemeral',
          'room': 'n1',
          'data': {'i': i},
        });
      }
      await a.expectNothingMore();
      b.send({'type': 'ping'});
      var relayed = 0;
      while (true) {
        final m = await b.next();
        if (m['type'] == 'ephemeral') {
          relayed++;
          continue;
        }
        expect(m['type'], 'pong');
        break;
      }
      expect(relayed, inInclusiveRange(4, 6));
    });
  });
}
