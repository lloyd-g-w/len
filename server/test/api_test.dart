import 'dart:convert';
import 'dart:io';

import 'package:len_sync_server/len_sync_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

const token = 'test-token-0123456789abcdef';

void main() {
  late RecordStore store;
  late Directory blobDir;
  late Handler handler;

  setUp(() {
    store = RecordStore.inMemory();
    blobDir = Directory.systemTemp.createTempSync('len_api_test_');
    handler = buildHandler(store: store, blobs: BlobStore.open(blobDir.path), token: token);
  });
  tearDown(() {
    store.close();
    blobDir.deleteSync(recursive: true);
  });

  Future<Response> send(
    String method,
    String path, {
    Object? body,
    String? auth = 'Bearer $token',
  }) async {
    return handler(
      Request(
        method,
        Uri.parse('http://localhost$path'),
        headers: {'authorization': ?auth},
        body: body is String ? body : (body == null ? null : jsonEncode(body)),
      ),
    );
  }

  Future<Map<String, Object?>> jsonOf(Response r) async =>
      jsonDecode(await r.readAsString()) as Map<String, Object?>;

  Map<String, Object?> record(String id, {int updatedAt = 1000}) => {
    'collection': 'notebooks',
    'id': id,
    'updatedAt': updatedAt,
    'deviceId': 'dev-1',
    'deleted': false,
    'data': {'title': 'Notebook $id'},
  };

  group('auth', () {
    test('health needs no token', () async {
      final r = await send('GET', '/v1/health', auth: null);
      expect(r.statusCode, 200);
      expect(r.headers['content-type'], startsWith('application/json'));
      expect(await jsonOf(r), {
        'status': 'ok',
        'protocol': 1,
        'maxBlobBytes': defaultMaxBlobBytes,
        'blobsCollectedAt': 0,
        'serverId': store.serverId,
      });
    });

    test('missing token is 401', () async {
      final r = await send('GET', '/v1/pull', auth: null);
      expect(r.statusCode, 401);
      expect((await jsonOf(r))['error'], isA<String>());
    });

    test('wrong token is 401', () async {
      for (final auth in ['Bearer wrong', 'Bearer ${token}x', 'Basic $token', token, 'Bearer ']) {
        final r = await send('POST', '/v1/push', auth: auth, body: {'records': <Object>[]});
        expect(r.statusCode, 401, reason: auth);
      }
    });

    test('scheme is case-insensitive', () async {
      final r = await send('GET', '/v1/pull', auth: 'bearer $token');
      expect(r.statusCode, 200);
    });
  });

  test('unknown route is 404', () async {
    final r = await send('GET', '/v1/nope');
    expect(r.statusCode, 404);
  });

  test('push then pull roundtrip', () async {
    var r = await send(
      'POST',
      '/v1/push',
      body: {
        'records': [record('a'), record('b'), record('a', updatedAt: 500)],
      },
    );
    expect(r.statusCode, 200);
    expect(await jsonOf(r), {'applied': 2, 'ignored': 1, 'serverSeq': 2});

    r = await send('GET', '/v1/pull?since=0&limit=1');
    expect(r.statusCode, 200);
    var page = await jsonOf(r);
    expect(page['records'], [
      {...record('a'), 'seq': 1},
    ]);
    expect(page['nextSince'], 1);
    expect(page['hasMore'], true);

    r = await send('GET', '/v1/pull?since=1');
    page = await jsonOf(r);
    expect((page['records'] as List).single, {...record('b'), 'seq': 2});
    expect(page['nextSince'], 2);
    expect(page['hasMore'], false);
  });

  test('recognised handwriting (recognised_text) is stored, replaced and tombstoned', () async {
    Map<String, Object?> text(int updatedAt, String device, Object? data) => {
      'collection': 'recognised_text',
      'id': 'page-1',
      'updatedAt': updatedAt,
      'deviceId': device,
      'deleted': data == null,
      'data': data,
    };
    final first = text(1000, 'phone', {
      'language': 'en-US',
      'lines': [
        ['0123456789abcdef0123', 'alpha beta'],
      ],
    });
    // Two phones recognised the same page: last write wins.
    final second = text(1000, 'tablet', {
      'language': 'en-US',
      'lines': [
        ['0123456789abcdef0123', 'alpha beta'],
        ['89abcdef012345670123', 'gamma'],
      ],
    });
    var r = await send(
      'POST',
      '/v1/push',
      body: {
        'records': [first, second],
      },
    );
    expect(await jsonOf(r), {'applied': 2, 'ignored': 0, 'serverSeq': 2});
    r = await send(
      'POST',
      '/v1/push',
      body: {
        'records': [first],
      },
    );
    expect((await jsonOf(r))['ignored'], 1);
    var page = await jsonOf(await send('GET', '/v1/pull'));
    expect(page['records'], [
      {...second, 'seq': 2},
    ]);

    final gone = text(2000, 'phone', null);
    r = await send(
      'POST',
      '/v1/push',
      body: {
        'records': [gone],
      },
    );
    expect((await jsonOf(r))['applied'], 1);
    page = await jsonOf(await send('GET', '/v1/pull?since=2'));
    expect(page['records'], [
      {...gone, 'seq': 3},
    ]);
  });

  group('a client ahead of the server (restored backup, replaced server)', () {
    test('pull is 409 and the server takes a new id', () async {
      await send(
        'POST',
        '/v1/push',
        body: {
          'records': [record('a')],
        },
      );
      final id = store.serverId;
      final r = await send('GET', '/v1/pull?since=2');
      expect(r.statusCode, 409);
      expect((await jsonOf(r))['error'], contains('history lost'));
      expect(store.serverId, isNot(id));
      expect((await send('GET', '/v1/pull?since=1')).statusCode, 200);
    });

    test('push is 409, applies nothing, and the server takes a new id', () async {
      final id = store.serverId;
      final r = await send(
        'POST',
        '/v1/push',
        body: {
          'since': 5,
          'records': [record('a')],
        },
      );
      expect(r.statusCode, 409);
      expect(store.currentSeq(), 0);
      expect(store.serverId, isNot(id));
      final ok = await send(
        'POST',
        '/v1/push',
        body: {
          'since': 0,
          'records': [record('a')],
        },
      );
      expect(ok.statusCode, 200);
    });

    test('push since must be a non-negative integer', () async {
      for (final since in [-1, '1', 1.5]) {
        final r = await send('POST', '/v1/push', body: {'since': since, 'records': <Object>[]});
        expect(r.statusCode, 400, reason: '$since');
      }
    });
  });

  test('pull defaults since to 0', () async {
    await send(
      'POST',
      '/v1/push',
      body: {
        'records': [record('a')],
      },
    );
    final page = await jsonOf(await send('GET', '/v1/pull'));
    expect(page['records'], hasLength(1));
  });

  group('400 on malformed requests', () {
    final cases = <String, Object>{
      'invalid JSON': '{"records": [',
      'non-object body': '[1,2]',
      'missing records': <String, Object>{},
      'records not array': {'records': 'x'},
      'invalid record': {
        'records': [
          {...record('a'), 'collection': 'Bad!'},
        ],
      },
      'data not object': {
        'records': [
          {...record('a'), 'data': 'str'},
        ],
      },
    };
    cases.forEach((name, body) {
      test(name, () async {
        final r = await send('POST', '/v1/push', body: body);
        expect(r.statusCode, 400);
        final json = await jsonOf(r);
        expect(json['error'], isA<String>());
        // Only an invalid record has an index (the client skips just it).
        final oneRecord = name == 'invalid record' || name == 'data not object';
        expect(json['index'], oneRecord ? 0 : isNull);
      });
    });

    test('one invalid record rejects the whole push', () async {
      final r = await send(
        'POST',
        '/v1/push',
        body: {
          'records': [
            record('ok'),
            {...record('bad'), 'id': ''},
          ],
        },
      );
      expect(r.statusCode, 400);
      expect(await jsonOf(r), {'error': startsWith('records[1]: '), 'index': 1});
      expect(store.currentSeq(), 0);
    });

    test('deeply nested data is 400, not a stack overflow', () async {
      const depth = 200000;
      final data = '${'{"a":' * depth}1${'}' * depth}';
      final rec = jsonEncode(record('deep')..remove('data'));
      final body = '{"records":[${rec.substring(0, rec.length - 1)},"data":$data}]}';
      final r = await send('POST', '/v1/push', body: body);
      expect(r.statusCode, 400);
      expect((await jsonOf(r))['index'], 0);
      expect(store.currentSeq(), 0);
    });

    for (final query in [
      'since=-1',
      'since=x',
      'since=0x10',
      'since=+1',
      'since=%201',
      'since=99999999999999999999',
      'limit=0',
      'limit=-5',
      'limit=abc',
    ]) {
      test('pull with $query', () async {
        final r = await send('GET', '/v1/pull?$query');
        expect(r.statusCode, 400);
      });
    }
  });

  test('pull limit above max is clamped', () async {
    final r = await send('GET', '/v1/pull?limit=5000');
    expect(r.statusCode, 200);
  });

  group('413', () {
    test('more than 1000 records', () async {
      final r = await send(
        'POST',
        '/v1/push',
        body: {
          'records': [for (var i = 0; i < 1001; i++) record('r$i')],
        },
      );
      expect(r.statusCode, 413);
      expect(store.currentSeq(), 0);
    });

    test('exactly 1000 records is accepted', () async {
      final r = await send(
        'POST',
        '/v1/push',
        body: {
          'records': [for (var i = 0; i < 1000; i++) record('r$i')],
        },
      );
      expect(r.statusCode, 200);
      expect(store.currentSeq(), 1000);
    });

    test('body larger than 32 MiB', () async {
      final big = 'x' * (32 * 1024 * 1024);
      final r = await send('POST', '/v1/push', body: '{"pad":"$big"}');
      expect(r.statusCode, 413);
    });

    test('streamed body over 32 MiB without Content-Length', () async {
      final chunk = List<int>.filled(1024 * 1024, 0x20);
      final request = Request(
        'POST',
        Uri.parse('http://localhost/v1/push'),
        headers: {'authorization': 'Bearer $token'},
        body: Stream.fromIterable(List.filled(33, chunk)),
      );
      expect(request.contentLength, isNull);
      final r = await handler(request);
      expect(r.statusCode, 413);
    });
  });

  test('unexpected errors are a JSON 500 with CORS headers and no details', () async {
    store.close();
    store = RecordStore.inMemory(); // for tearDown
    final r = await send(
      'POST',
      '/v1/push',
      body: {
        'records': [record('a')],
      },
    );
    // The handler still holds the closed store.
    expect(r.statusCode, 500);
    expect(r.headers['access-control-allow-origin'], '*');
    expect(await jsonOf(r), {'error': 'internal server error'});
  });

  test('constantTimeEquals', () {
    expect(constantTimeEquals([1, 2, 3], [1, 2, 3]), isTrue);
    expect(constantTimeEquals([1, 2, 3], [1, 2, 4]), isFalse);
    expect(constantTimeEquals([1, 2], [1, 2, 0]), isFalse);
    expect(constantTimeEquals([], []), isTrue);
  });
}
