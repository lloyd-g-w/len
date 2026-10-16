import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:len_sync_server/len_sync_server.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

const token = 'test-token-0123456789abcdef';

/// The events of an SSE body: `data` payloads decoded, comments as
/// `': <text>'`.
class Events {
  Events(Stream<List<int>> body) {
    _sub = body.transform(utf8.decoder).listen((text) {
      _buffer.write(text);
      var all = _buffer.toString();
      int end;
      while ((end = all.indexOf('\n\n')) >= 0) {
        _add(all.substring(0, end));
        all = all.substring(end + 2);
      }
      _buffer
        ..clear()
        ..write(all);
    }, onDone: () => done = true);
  }

  late final StreamSubscription<String> _sub;
  final _buffer = StringBuffer();
  final _queue = Queue<Object>();
  final _waiting = Queue<Completer<Object>>();
  bool done = false;

  void _add(String block) {
    final Object event = block.startsWith(':')
        ? block
        : jsonDecode(block.substring('data: '.length)) as Map<String, Object?>;
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete(event);
    } else {
      _queue.add(event);
    }
  }

  /// The next event (fails the test after [timeout]).
  Future<Object> next({Duration timeout = const Duration(seconds: 5)}) {
    if (_queue.isNotEmpty) return Future.value(_queue.removeFirst());
    final c = Completer<Object>();
    _waiting.add(c);
    return c.future.timeout(
      timeout,
      onTimeout: () {
        _waiting.remove(c);
        throw TimeoutException('no event', timeout);
      },
    );
  }

  /// The next data event, skipping heartbeats.
  Future<Object> data({Duration timeout = const Duration(seconds: 5)}) async {
    final watch = Stopwatch()..start();
    while (true) {
      final left = timeout - watch.elapsed;
      if (left <= Duration.zero) throw TimeoutException('no data', timeout);
      final event = await next(timeout: left);
      if (event is! String) return event;
    }
  }

  Future<void> cancel() => _sub.cancel();
}

void main() {
  late RecordStore store;
  late Directory blobDir;
  late ChangeEvents events;
  late Handler handler;

  setUp(() {
    store = RecordStore.inMemory();
    blobDir = Directory.systemTemp.createTempSync('len_events_test_');
    events = ChangeEvents(heartbeat: const Duration(milliseconds: 50), maxStreams: 300);
    handler = buildHandler(
      store: store,
      blobs: BlobStore.open(blobDir.path),
      token: token,
      events: events,
    );
  });
  tearDown(() async {
    await events.close();
    store.close();
    blobDir.deleteSync(recursive: true);
  });

  Future<Response> send(String method, String path, {Object? body, String? auth = token}) =>
      Future.sync(
        () => handler(
          Request(
            method,
            Uri.parse('http://localhost$path'),
            headers: {if (auth != null) 'authorization': 'Bearer $auth'},
            body: body == null ? null : jsonEncode(body),
          ),
        ),
      );

  Map<String, Object?> record(String id, {int updatedAt = 1000}) => {
    'collection': 'notebooks',
    'id': id,
    'updatedAt': updatedAt,
    'deviceId': 'dev-1',
    'deleted': false,
    'data': {'title': id},
  };

  Future<Response> push(List<Map<String, Object?>> records, {int since = 0}) =>
      send('POST', '/v1/push', body: {'since': since, 'records': records});

  Future<Events> open() async {
    final r = await send('GET', '/v1/events');
    expect(r.statusCode, 200);
    return Events(r.read());
  }

  test('needs the token', () async {
    expect((await send('GET', '/v1/events', auth: null)).statusCode, 401);
    expect((await send('GET', '/v1/events', auth: 'wrong-token-0000000000')).statusCode, 401);
    expect(events.streams, 0);
  });

  test('streams unbuffered, uncached and with CORS headers', () async {
    final r = await send('GET', '/v1/events');
    expect(r.statusCode, 200);
    expect(r.headers['content-type'], 'text/event-stream; charset=utf-8');
    expect(r.headers['cache-control'], contains('no-cache'));
    expect(r.headers['cache-control'], contains('no-transform'));
    expect(r.headers['x-accel-buffering'], 'no');
    expect(r.headers['access-control-allow-origin'], '*');
    expect(r.context['shelf.io.buffer_output'], false);
    await Events(r.read()).cancel();
  });

  test('starts with the newest seq and the server id', () async {
    await push([record('a'), record('b')]);
    final stream = await open();
    expect(await stream.next(), {'seq': 2, 'serverId': store.serverId});
    await stream.cancel();
  });

  test('a push that stores something is announced, one storing nothing is not', () async {
    final stream = await open();
    expect(await stream.next(), {'seq': 0, 'serverId': store.serverId});
    await push([record('a')]);
    expect(await stream.data(), {'seq': 1, 'serverId': store.serverId});
    // Ignored (an older version): no event.
    await push([record('a', updatedAt: 1)]);
    await expectLater(
      stream.data(timeout: const Duration(milliseconds: 300)),
      throwsA(isA<TimeoutException>()),
    );
    await push([record('a', updatedAt: 2000), record('c')]);
    expect(await stream.data(), {'seq': 3, 'serverId': store.serverId});
    await stream.cancel();
  });

  test('idle streams carry heartbeats', () async {
    final stream = await open();
    await stream.next();
    for (var i = 0; i < 3; i++) {
      expect(await stream.next(), ': ping');
    }
    await stream.cancel();
  });

  test('a lost history announces the new server id', () async {
    final stream = await open();
    final before = store.serverId;
    await stream.next();
    expect((await push([record('a')], since: 7)).statusCode, 409);
    expect(store.serverId, isNot(before));
    expect(await stream.data(), {'seq': 0, 'serverId': store.serverId});
    await stream.cancel();
  });

  test('many clients all hear of a push; closed ones are let go', () async {
    final streams = [for (var i = 0; i < 250; i++) await open()];
    expect(events.streams, 250);
    for (final s in streams) {
      expect(await s.data(), {'seq': 0, 'serverId': store.serverId});
    }
    await push([record('a')]);
    for (final s in streams) {
      expect(await s.data(), {'seq': 1, 'serverId': store.serverId});
    }
    for (final s in streams.take(100)) {
      await s.cancel();
    }
    expect(events.streams, 150);
    for (final s in streams.skip(100)) {
      await s.cancel();
    }
    expect(events.streams, 0);
  });

  test('beyond the limit streams are refused with 503', () async {
    final small = ChangeEvents(maxStreams: 2);
    final h = buildHandler(
      store: store,
      blobs: BlobStore.open(blobDir.path),
      token: token,
      events: small,
    );
    Future<Response> get() => Future.sync(
      () => h(
        Request(
          'GET',
          Uri.parse('http://localhost/v1/events'),
          headers: {'authorization': 'Bearer $token'},
        ),
      ),
    );
    final a = Events((await get()).read());
    final b = Events((await get()).read());
    final refused = await get();
    expect(refused.statusCode, 503);
    expect(refused.headers['retry-after'], isNotNull);
    await a.cancel();
    final c = await get();
    expect(c.statusCode, 200);
    await Events(c.read()).cancel();
    await b.cancel();
    await small.close();
  });

  test('closing ends every stream and refuses new ones', () async {
    final a = await open();
    final b = await open();
    await a.next();
    await b.next();
    await events.close();
    await pumpEventQueue();
    expect(a.done, isTrue);
    expect(b.done, isTrue);
    expect(events.streams, 0);
    expect((await send('GET', '/v1/events')).statusCode, 503);
  });

  group('over a real socket', () {
    late HttpServer server;
    late HttpClient client;

    setUp(() async {
      server = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, 0);
      client = HttpClient();
    });
    tearDown(() async {
      client.close(force: true);
      await server.close(force: true);
    });

    Future<HttpClientResponse> get() async {
      final request = await client.get('127.0.0.1', server.port, '/v1/events');
      request.headers.set('authorization', 'Bearer $token');
      return request.close();
    }

    test('events arrive as they happen (not buffered)', () async {
      final response = await get();
      expect(response.statusCode, 200);
      final stream = Events(response);
      expect(await stream.next(), {'seq': 0, 'serverId': store.serverId});
      await push([record('a')]);
      expect(await stream.data(), {'seq': 1, 'serverId': store.serverId});
      await stream.cancel();
    });

    test('a client hanging up releases its stream', () async {
      final response = await get();
      final stream = Events(response);
      await stream.next();
      expect(events.streams, 1);
      await stream.cancel();
      client.close(force: true);
      // The server notices when it next writes (a heartbeat at the latest).
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (events.streams > 0 && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(events.streams, 0);
    });
  });
}
