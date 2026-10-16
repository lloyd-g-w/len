import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:len_sync_server/len_sync_server.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

// Requests repeated after a lost answer, sent twice at once, broken off
// while sending or cut short, and a server restarting between them: pushes
// and blob uploads are idempotent, and nothing half-received is stored.

const token = 'test-token-0123456789abcdef';

void main() {
  late Directory dir;
  late RecordStore store;
  late BlobStore blobs;
  late Handler handler;

  void open() {
    store = RecordStore.open('${dir.path}/len.db');
    blobs = BlobStore.open('${dir.path}/blobs');
    handler = buildHandler(store: store, blobs: blobs, token: token);
  }

  /// Closes the database and opens it again, like a server restarting.
  void restart() {
    store.close();
    open();
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('len_retry_test_');
    open();
  });
  tearDown(() {
    store.close();
    dir.deleteSync(recursive: true);
  });

  Future<Response> send(String method, String path, {Object? body}) async => handler(
    Request(
      method,
      Uri.parse('http://localhost$path'),
      headers: {'authorization': 'Bearer $token'},
      body: body,
    ),
  );

  Future<Map<String, Object?>> jsonOf(Response r) async =>
      jsonDecode(await r.readAsString()) as Map<String, Object?>;

  Map<String, Object?> record(
    String id,
    int updatedAt, {
    String device = 'a',
    bool deleted = false,
  }) => {
    'collection': 'notebooks',
    'id': id,
    'updatedAt': updatedAt,
    'deviceId': device,
    'deleted': deleted,
    'data': deleted ? null : {'title': '$id at $updatedAt by $device'},
  };

  String push(List<Map<String, Object?>> records, {int since = 0}) =>
      jsonEncode({'since': since, 'records': records});

  /// The whole feed, as `collection/id@updatedAt/deviceId` by seq.
  List<String> feed() => [
    for (final r in store.pull(since: 0, limit: 1000).records)
      '${r.seq}:${r.collection}/${r.id}@${r.updatedAt}/${r.deviceId}${r.deleted ? '✝' : ''}',
  ];

  group('push', () {
    test('sent again after its answer was lost: applies nothing new', () async {
      final body = push([record('n1', 10), record('n2', 10), record('n3', 10, deleted: true)]);
      final first = await jsonOf(await send('POST', '/v1/push', body: body));
      expect(first, {'applied': 3, 'ignored': 0, 'serverSeq': 3});
      final before = feed();
      final again = await jsonOf(await send('POST', '/v1/push', body: body));
      expect(again, {'applied': 0, 'ignored': 3, 'serverSeq': 3});
      expect(feed(), before);
    });

    test('a late retry never rolls back what another device wrote since', () async {
      final body = push([record('n1', 10)]);
      await send('POST', '/v1/push', body: body);
      // Another device edits and deletes; then the retry arrives.
      await send('POST', '/v1/push', body: push([record('n1', 20, device: 'b')]));
      await send('POST', '/v1/push', body: push([record('n2', 30, device: 'b', deleted: true)]));
      final before = feed();
      expect(await jsonOf(await send('POST', '/v1/push', body: body)), containsPair('applied', 0));
      expect(await jsonOf(await send('POST', '/v1/push', body: push([record('n2', 25)]))), {
        'applied': 0,
        'ignored': 1,
        'serverSeq': 3,
      });
      expect(feed(), before);
    });

    test('sent twice at once: stored once', () async {
      final body = push([for (var i = 0; i < 50; i++) record('n$i', 10)]);
      final answers = await Future.wait([
        for (var i = 0; i < 3; i++) send('POST', '/v1/push', body: body),
      ]);
      expect([for (final a in answers) a.statusCode], [200, 200, 200]);
      final applied = [for (final a in answers) (await jsonOf(a))['applied']];
      expect(applied..sort(), [0, 0, 50]);
      expect(store.currentSeq(), 50);
    });

    test('sent again after the server restarted: applies nothing new', () async {
      final body = push([record('n1', 10), record('n2', 11)]);
      await send('POST', '/v1/push', body: body);
      final id = store.serverId;
      restart();
      expect(store.serverId, id, reason: 'a restart keeps the history');
      final again = await jsonOf(
        await send('POST', '/v1/push', body: push([record('n1', 10)], since: 2)),
      );
      expect(again, {'applied': 0, 'ignored': 1, 'serverSeq': 2});
      expect(feed(), ['1:notebooks/n1@10/a', '2:notebooks/n2@11/a']);
    });

    test('broken off while sending: nothing is applied', () async {
      final body = utf8.encode(push([record('n1', 10), record('n2', 10)]));
      final broken = StreamController<List<int>>()
        ..add(body.sublist(0, body.length ~/ 2))
        ..addError(const SocketException('Connection reset by peer'));
      unawaited(broken.close());
      final answer = await send('POST', '/v1/push', body: broken.stream);
      expect(answer.statusCode, 500);
      expect(store.currentSeq(), 0);
    });

    test('cut short (a body ending early): 400, nothing applied', () async {
      final body = push([record('n1', 10), record('n2', 10)]);
      for (final cut in [1, body.length ~/ 3, body.length - 1]) {
        final answer = await send('POST', '/v1/push', body: body.substring(0, cut));
        expect(answer.statusCode, 400, reason: 'cut at $cut');
      }
      expect(store.currentSeq(), 0);
    });
  });

  group('pull', () {
    test('pages read across restarts add up to the whole feed', () async {
      for (var i = 0; i < 30; i++) {
        await send('POST', '/v1/push', body: push([record('n${i % 12}', 10 + i)]));
      }
      final whole = feed();
      final paged = <String>[];
      var since = 0;
      while (true) {
        final page = await jsonOf(await send('GET', '/v1/pull?since=$since&limit=4'));
        for (final r in (page['records']! as List).cast<Map<String, Object?>>()) {
          paged.add('${r['seq']}:${r['collection']}/${r['id']}@${r['updatedAt']}/${r['deviceId']}');
        }
        restart();
        if (page['hasMore'] != true) break;
        since = page['nextSince']! as int;
      }
      expect(paged, whole);
      // The same page again (its answer lost) is the same page.
      final a = await (await send('GET', '/v1/pull?since=3&limit=4')).readAsString();
      final b = await (await send('GET', '/v1/pull?since=3&limit=4')).readAsString();
      expect(a, b);
    });
  });

  group('blob upload', () {
    final data = utf8.encode('the bytes of a recording ' * 100);
    final sha = sha256.convert(data).toString();

    List<FileSystemEntity> temp() => Directory('${dir.path}/blobs/tmp').listSync();

    test('sent again after its answer was lost: 200, stored once', () async {
      for (var i = 0; i < 3; i++) {
        final answer = await send('PUT', '/v1/blobs/$sha', body: data);
        expect(answer.statusCode, 200);
        expect(await jsonOf(answer), {'sha256': sha, 'size': data.length});
      }
      expect(File(blobs.pathFor(sha)).readAsBytesSync(), data);
      expect(blobs.list().toList(), [sha]);
      expect(temp(), isEmpty);
    });

    test('sent several times at once: all 200, stored intact', () async {
      final answers = await Future.wait([
        for (var i = 0; i < 4; i++)
          send(
            'PUT',
            '/v1/blobs/$sha',
            body: Stream.fromIterable([
              for (final b in data) [b],
            ]),
          ),
      ]);
      expect([for (final a in answers) a.statusCode], [200, 200, 200, 200]);
      expect(File(blobs.pathFor(sha)).readAsBytesSync(), data);
      expect(temp(), isEmpty);
    });

    test('broken off while sending: nothing stored, the retry works', () async {
      final broken = StreamController<List<int>>()
        ..add(data.sublist(0, data.length ~/ 2))
        ..addError(const SocketException('Connection reset by peer'));
      unawaited(broken.close());
      final answer = await send('PUT', '/v1/blobs/$sha', body: broken.stream);
      expect(answer.statusCode, 500);
      expect(blobs.has(sha), isFalse);
      expect(temp(), isEmpty);
      expect((await send('PUT', '/v1/blobs/$sha', body: data)).statusCode, 200);
      expect(File(blobs.pathFor(sha)).readAsBytesSync(), data);
    });

    test('cut short (ending early, cleanly): 400 hash mismatch, nothing stored', () async {
      final answer = await send('PUT', '/v1/blobs/$sha', body: data.sublist(0, data.length - 7));
      expect(answer.statusCode, 400);
      expect(blobs.has(sha), isFalse);
      expect(temp(), isEmpty);
    });

    test('a retry finishing while the first attempt is still sending', () async {
      final first = StreamController<List<int>>();
      final firstAnswer = send('PUT', '/v1/blobs/$sha', body: first.stream);
      first.add(data.sublist(0, 10));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect((await send('PUT', '/v1/blobs/$sha', body: data)).statusCode, 200);
      // The first connection breaks: it must not take the stored blob along.
      first.addError(const SocketException('Connection reset by peer'));
      unawaited(first.close());
      expect((await firstAnswer).statusCode, 500);
      expect(File(blobs.pathFor(sha)).readAsBytesSync(), data);
      expect(temp(), isEmpty);
    });

    test('over real HTTP: a client hanging up mid-upload leaves nothing behind', () async {
      final server = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final socket = await Socket.connect(InternetAddress.loopbackIPv4, server.port);
      socket.write(
        'PUT /v1/blobs/$sha HTTP/1.1\r\nHost: localhost\r\n'
        'Authorization: Bearer $token\r\nContent-Length: ${data.length}\r\n\r\n',
      );
      socket.add(data.sublist(0, data.length ~/ 2));
      await socket.flush();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      socket.destroy();
      for (var i = 0; i < 100 && temp().isNotEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(temp(), isEmpty);
      expect(blobs.has(sha), isFalse);
      // The upload sent again over a new connection is stored.
      final client = HttpClient();
      addTearDown(client.close);
      final request = await client.put('127.0.0.1', server.port, '/v1/blobs/$sha')
        ..headers.set('authorization', 'Bearer $token')
        ..add(data);
      final response = await request.close();
      expect(response.statusCode, 200);
      await response.drain<void>();
      expect(File(blobs.pathFor(sha)).readAsBytesSync(), data);
    });
  });
}
