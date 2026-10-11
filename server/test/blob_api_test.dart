import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:len_sync_server/len_sync_server.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

const token = 'test-token-0123456789abcdef';
const maxBlobBytes = 64;

void main() {
  late RecordStore store;
  late Directory dir;
  late BlobStore blobs;
  late Handler handler;

  setUp(() {
    store = RecordStore.inMemory();
    dir = Directory.systemTemp.createTempSync('len_blob_api_test_');
    blobs = BlobStore.open(dir.path);
    handler = buildHandler(store: store, blobs: blobs, token: token, maxBlobBytes: maxBlobBytes);
  });
  tearDown(() {
    store.close();
    dir.deleteSync(recursive: true);
  });

  final data = utf8.encode('some pdf bytes');
  final sha = sha256.convert(data).toString();

  Future<Response> send(
    String method,
    String path, {
    Object? body,
    String? auth = 'Bearer $token',
  }) async => handler(
    Request(
      method,
      Uri.parse('http://localhost$path'),
      headers: {'authorization': ?auth},
      body: body,
    ),
  );

  Future<Map<String, Object?>> jsonOf(Response r) async =>
      jsonDecode(await r.readAsString()) as Map<String, Object?>;

  test('health advertises the blob size limit', () async {
    final r = await send('GET', '/v1/health', auth: null);
    final json = await jsonOf(r);
    expect(json['maxBlobBytes'], maxBlobBytes);
  });

  test('upload, then GET returns the bytes', () async {
    var r = await send('PUT', '/v1/blobs/$sha', body: data);
    expect(r.statusCode, 200);
    expect(await jsonOf(r), {'sha256': sha, 'size': data.length});
    expect(blobs.has(sha), isTrue);

    r = await send('GET', '/v1/blobs/$sha');
    expect(r.statusCode, 200);
    expect(r.headers['content-type'], 'application/octet-stream');
    expect(r.headers['content-length'], '${data.length}');
    expect(await r.read().expand((c) => c).toList(), data);
  });

  test('re-upload is idempotent', () async {
    await send('PUT', '/v1/blobs/$sha', body: data);
    final r = await send('PUT', '/v1/blobs/$sha', body: data);
    expect(r.statusCode, 200);
    expect(await jsonOf(r), {'sha256': sha, 'size': data.length});
  });

  test('hash mismatch is 400 and stores nothing', () async {
    final r = await send('PUT', '/v1/blobs/${'0' * 64}', body: data);
    expect(r.statusCode, 400);
    expect(await jsonOf(r), {'error': 'hash mismatch'});
    expect(blobs.has('0' * 64), isFalse);
  });

  for (final bad in ['abc', sha.toUpperCase(), '${sha}0', 'z' * 64]) {
    test('invalid sha "$bad" is 400', () async {
      for (final method in ['PUT', 'GET', 'HEAD']) {
        final r = await send(method, '/v1/blobs/$bad', body: method == 'PUT' ? data : null);
        expect(r.statusCode, 400, reason: method);
      }
    });
  }

  group('413', () {
    final big = List<int>.filled(maxBlobBytes + 1, 7);
    final bigSha = sha256.convert(big).toString();

    test('Content-Length over the limit', () async {
      final r = await send('PUT', '/v1/blobs/$bigSha', body: big);
      expect(r.statusCode, 413);
      expect((await jsonOf(r))['error'], isA<String>());
      expect(blobs.has(bigSha), isFalse);
    });

    test('streamed body over the limit', () async {
      final request = Request(
        'PUT',
        Uri.parse('http://localhost/v1/blobs/$bigSha'),
        headers: {'authorization': 'Bearer $token'},
        body: Stream.fromIterable([big.sublist(0, 40), big.sublist(40)]),
      );
      expect(request.contentLength, isNull);
      final r = await handler(request);
      expect(r.statusCode, 413);
      expect(blobs.has(bigSha), isFalse);
      expect(Directory('${dir.path}/tmp').listSync(), isEmpty);
    });
  });

  test('stalled upload is 408 and stores nothing', () async {
    final h = buildHandler(
      store: store,
      blobs: blobs,
      token: token,
      blobIdleTimeout: const Duration(milliseconds: 50),
    );
    final body = StreamController<List<int>>()..add(data.sublist(0, 2));
    final r = await h(
      Request(
        'PUT',
        Uri.parse('http://localhost/v1/blobs/$sha'),
        headers: {'authorization': 'Bearer $token', 'content-length': '${data.length}'},
        body: body.stream,
      ),
    );
    expect(r.statusCode, 408);
    expect(await jsonOf(r), {'error': 'upload stalled'});
    expect(blobs.has(sha), isFalse);
    expect(Directory('${dir.path}/tmp').listSync(), isEmpty);
    await body.close();
  });

  test('over real HTTP: a stalled upload is dropped and its temp file removed', () async {
    final h = buildHandler(
      store: store,
      blobs: blobs,
      token: token,
      blobIdleTimeout: const Duration(milliseconds: 200),
    );
    final server = await shelf_io.serve(h, InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, server.port);
    addTearDown(socket.destroy);
    socket.write(
      'PUT /v1/blobs/$sha HTTP/1.1\r\nHost: localhost\r\n'
      'Authorization: Bearer $token\r\nContent-Length: ${data.length}\r\n\r\n',
    );
    socket.add(data.sublist(0, 2)); // ...then stall.
    // Completes once the server closes the connection. dart:io drops a
    // connection whose request body is abandoned, so the 408 may not arrive.
    final response = await utf8.decoder.bind(socket).join().timeout(const Duration(seconds: 5));
    expect(response, anyOf(isEmpty, startsWith('HTTP/1.1 408')));
    // The temp file is removed asynchronously, right after the abort.
    final tmp = Directory('${dir.path}/tmp');
    for (var i = 0; i < 50 && tmp.listSync().isNotEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(tmp.listSync(), isEmpty);
    expect(blobs.has(sha), isFalse);
  });

  test('push body limit does not apply to blobs', () async {
    final big = List<int>.filled(33 * 1024 * 1024, 1);
    final bigSha = sha256.convert(big).toString();
    final h = buildHandler(
      store: store,
      blobs: blobs,
      token: token,
      maxBlobBytes: 40 * 1024 * 1024,
    );
    final r = await h(
      Request(
        'PUT',
        Uri.parse('http://localhost/v1/blobs/$bigSha'),
        headers: {'authorization': 'Bearer $token'},
        body: big,
      ),
    );
    expect(r.statusCode, 200);
    expect(blobs.size(bigSha), big.length);
  });

  test('unauthenticated requests are 401', () async {
    for (final method in ['PUT', 'GET', 'HEAD']) {
      final r = await send(
        method,
        '/v1/blobs/$sha',
        auth: method == 'GET' ? 'Bearer wrong' : null,
        body: method == 'PUT' ? data : null,
      );
      expect(r.statusCode, 401, reason: method);
    }
    expect(blobs.has(sha), isFalse);
  });

  test('GET missing is 404', () async {
    final r = await send('GET', '/v1/blobs/$sha');
    expect(r.statusCode, 404);
    expect(await jsonOf(r), {'error': 'not found'});
  });

  test('HEAD is 200 with Content-Length and no body, 404 when missing', () async {
    var r = await send('HEAD', '/v1/blobs/$sha');
    expect(r.statusCode, 404);
    expect(await r.readAsString(), isEmpty);

    await send('PUT', '/v1/blobs/$sha', body: data);
    r = await send('HEAD', '/v1/blobs/$sha');
    expect(r.statusCode, 200);
    expect(r.headers['content-length'], '${data.length}');
    expect(r.headers['content-type'], 'application/octet-stream');
    expect(await r.readAsString(), isEmpty);
  });

  test('over real HTTP: PUT, HEAD and GET', () async {
    final server = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, 0);
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await server.close(force: true);
    });
    Future<HttpClientResponse> call(String method) async {
      final req = await client.open(method, '127.0.0.1', server.port, '/v1/blobs/$sha');
      req.headers.set('authorization', 'Bearer $token');
      if (method == 'PUT') req.add(data);
      return req.close();
    }

    var res = await call('HEAD');
    expect(res.statusCode, 404);
    await res.drain<void>();

    res = await call('PUT');
    expect(res.statusCode, 200);
    expect(jsonDecode(await utf8.decodeStream(res)), {'sha256': sha, 'size': data.length});

    res = await call('HEAD');
    expect(res.statusCode, 200);
    expect(res.contentLength, data.length);
    expect(await res.expand((c) => c).toList(), isEmpty);

    res = await call('GET');
    expect(res.statusCode, 200);
    expect(res.headers.contentType?.mimeType, 'application/octet-stream');
    expect(res.contentLength, data.length);
    expect(await res.expand((c) => c).toList(), data);
  });
}
