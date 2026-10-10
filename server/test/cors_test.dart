import 'dart:io';

import 'package:len_sync_server/len_sync_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

const token = 'test-token-0123456789abcdef';
const webOrigin = 'https://len.example.com';

void main() {
  late RecordStore store;
  late Directory blobDir;

  setUp(() {
    store = RecordStore.inMemory();
    blobDir = Directory.systemTemp.createTempSync('len_cors_test_');
  });
  tearDown(() {
    store.close();
    blobDir.deleteSync(recursive: true);
  });

  Handler handlerFor(CorsPolicy cors) =>
      buildHandler(store: store, blobs: BlobStore.open(blobDir.path), token: token, cors: cors);

  Future<Response> send(
    Handler handler,
    String method,
    String path, {
    String? origin = webOrigin,
    String? auth = 'Bearer $token',
    Map<String, String> headers = const {},
  }) async {
    return handler(
      Request(
        method,
        Uri.parse('http://localhost$path'),
        headers: {'origin': ?origin, 'authorization': ?auth, ...headers},
      ),
    );
  }

  Future<Response> preflight(Handler handler, String path, {String? origin = webOrigin}) => send(
    handler,
    'OPTIONS',
    path,
    origin: origin,
    auth: null,
    headers: {
      'access-control-request-method': 'PUT',
      'access-control-request-headers': 'authorization, content-type',
    },
  );

  group('default policy (any origin)', () {
    late Handler handler;
    setUp(() => handler = handlerFor(const CorsPolicy.any()));

    test('preflight is 204 with allow headers and needs no auth', () async {
      for (final path in ['/v1/pull', '/v1/push', '/v1/blobs/${'a' * 64}', '/v1/health']) {
        final r = await preflight(handler, path);
        expect(r.statusCode, 204, reason: path);
        expect(r.headers['access-control-allow-origin'], '*');
        expect(r.headers['access-control-allow-methods'], 'GET, HEAD, POST, PUT, OPTIONS');
        expect(r.headers['access-control-allow-headers'], 'Authorization, Content-Type');
        expect(r.headers['access-control-max-age'], '86400');
        expect(r.headers['access-control-allow-credentials'], isNull);
        expect(r.headers['vary'], isNull);
      }
    });

    test('authorized response carries allow and expose headers', () async {
      final r = await send(handler, 'GET', '/v1/pull');
      expect(r.statusCode, 200);
      expect(r.headers['access-control-allow-origin'], '*');
      expect(r.headers['access-control-expose-headers'], 'Content-Length, Content-Type');
      expect(r.headers['access-control-allow-credentials'], isNull);
    });

    test('401, 404 and 400 responses carry CORS headers', () async {
      final unauthorized = await send(handler, 'GET', '/v1/pull', auth: null);
      expect(unauthorized.statusCode, 401);
      expect(unauthorized.headers['access-control-allow-origin'], '*');
      expect(unauthorized.headers['access-control-expose-headers'], isNotNull);

      final notFound = await send(handler, 'GET', '/v1/blobs/${'b' * 64}');
      expect(notFound.statusCode, 404);
      expect(notFound.headers['access-control-allow-origin'], '*');

      final badRequest = await send(handler, 'GET', '/v1/pull?since=x');
      expect(badRequest.statusCode, 400);
      expect(badRequest.headers['access-control-allow-origin'], '*');
    });
  });

  group('allow-list policy', () {
    late Handler handler;
    setUp(() => handler = handlerFor(CorsPolicy.allowList([webOrigin, 'http://localhost:5173'])));

    test('echoes an allowed origin with Vary: Origin', () async {
      final pre = await preflight(handler, '/v1/push');
      expect(pre.statusCode, 204);
      expect(pre.headers['access-control-allow-origin'], webOrigin);
      expect(pre.headers['vary'], 'Origin');

      final r = await send(handler, 'GET', '/v1/pull', origin: 'http://localhost:5173');
      expect(r.statusCode, 200);
      expect(r.headers['access-control-allow-origin'], 'http://localhost:5173');
      expect(r.headers['access-control-expose-headers'], isNotNull);
      expect(r.headers['vary'], 'Origin');

      final unauthorized = await send(handler, 'GET', '/v1/pull', auth: null);
      expect(unauthorized.statusCode, 401);
      expect(unauthorized.headers['access-control-allow-origin'], webOrigin);
    });

    test('origin matching is case-insensitive', () async {
      final r = await send(handler, 'GET', '/v1/health', origin: 'HTTPS://LEN.example.com');
      expect(r.headers['access-control-allow-origin'], 'HTTPS://LEN.example.com');
    });

    test('denies other origins', () async {
      final pre = await preflight(handler, '/v1/push', origin: 'https://evil.example');
      expect(pre.statusCode, 403);
      expect(pre.headers['access-control-allow-origin'], isNull);
      expect(pre.headers['access-control-allow-methods'], isNull);

      final r = await send(handler, 'GET', '/v1/pull', origin: 'https://evil.example');
      expect(r.statusCode, 200);
      expect(r.headers['access-control-allow-origin'], isNull);
      expect(r.headers['access-control-expose-headers'], isNull);
      expect(r.headers['vary'], 'Origin');

      final noOrigin = await send(handler, 'GET', '/v1/pull', origin: null);
      expect(noOrigin.headers['access-control-allow-origin'], isNull);
    });
  });

  group('disabled policy', () {
    test('sends no CORS headers and does not answer OPTIONS', () async {
      final handler = handlerFor(const CorsPolicy.disabled());
      final r = await send(handler, 'GET', '/v1/pull');
      expect(r.statusCode, 200);
      expect(r.headers.keys.where((k) => k.startsWith('access-control-')), isEmpty);

      final pre = await preflight(handler, '/v1/pull');
      expect(pre.statusCode, 401);
      expect(pre.headers['access-control-allow-origin'], isNull);
    });
  });
}
