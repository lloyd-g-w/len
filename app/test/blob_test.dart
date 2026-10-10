import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/blob_store.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/sync/sync_api.dart';

/// Fake blob endpoints plus an accept-everything push/pull.
class FakeBlobServer {
  static const token = 'secret-token-123456';
  final Map<String, Uint8List> blobs = {};
  final List<String> log = [];

  late final MockClient client = MockClient((request) async {
    if (request.headers['Authorization'] != 'Bearer $token') {
      return http.Response('{"error":"unauthorized"}', 401);
    }
    final path = request.url.path;
    if (path.startsWith('/v1/blobs/')) {
      final sha = path.substring('/v1/blobs/'.length);
      log.add('${request.method} $sha');
      switch (request.method) {
        case 'HEAD':
          return http.Response('', blobs.containsKey(sha) ? 200 : 404);
        case 'GET':
          final b = blobs[sha];
          return b == null
              ? http.Response('{"error":"not found"}', 404)
              : http.Response.bytes(b, 200);
        case 'PUT':
          if (sha256.convert(request.bodyBytes).toString() != sha) {
            return http.Response('{"error":"hash mismatch"}', 400);
          }
          blobs[sha] = request.bodyBytes;
          return http.Response(jsonEncode({'sha256': sha, 'size': request.bodyBytes.length}), 200);
      }
    }
    if (path == '/v1/push') {
      log.add('push');
      return http.Response('{"applied":0,"ignored":0,"serverSeq":0}', 200);
    }
    if (path == '/v1/pull') {
      return http.Response('{"records":[],"nextSince":0,"hasMore":false}', 200);
    }
    return http.Response('', 404);
  });
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('len_blob_test_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('blob store is content addressed and idempotent', () async {
    final store = BlobStore(AppDatabase.inMemory(), dir);
    final bytes = Uint8List.fromList(utf8.encode('%PDF-1.4 hello'));
    final sha = await store.putBytes(bytes, mime: 'application/pdf');
    expect(sha, sha256.convert(bytes).toString());
    expect(store.has(sha), isTrue);
    expect(await store.read(sha), bytes);
    expect(store.fileOf(sha).path, endsWith('${sha.substring(0, 2)}/$sha'));
    expect(await store.putBytes(bytes, mime: 'application/pdf'), sha);
    expect(store.pendingUploads(), [sha]);

    final file = File('${dir.path}/in.pdf')..writeAsBytesSync(bytes);
    expect(await store.putFile(file, mime: 'application/pdf'), sha);
    expect(await BlobStore.hashFile(file), sha);

    store.markUploaded(sha);
    expect(store.pendingUploads(), isEmpty);
    store.markAllNotUploaded();
    expect(store.pendingUploads(), [sha]);
    expect(() => store.fileOf('../../etc/passwd'), throwsArgumentError);
  });

  test('downloaded blobs are verified', () async {
    final store = BlobStore(AppDatabase.inMemory(), dir);
    final bytes = Uint8List.fromList([1, 2, 3]);
    final sha = sha256.convert(bytes).toString();
    await expectLater(store.putDownloaded(sha, Uint8List.fromList([9])), throwsFormatException);
    expect(store.has(sha), isFalse);
    await store.putDownloaded(sha, bytes);
    expect(store.has(sha), isTrue);
    expect(store.pendingUploads(), isEmpty); // The server has it.
  });

  test('sync uploads blobs before records; other devices fetch lazily', () async {
    final server = FakeBlobServer();
    SyncApi api(String url, String token) =>
        SyncApi(baseUrl: url, token: token, client: server.client);
    final a = AppServices.create(AppDatabase.inMemory(), blobDirectory: dir, syncApiFactory: api);
    final bDir = Directory.systemTemp.createTempSync('len_blob_b_');
    addTearDown(() => bDir.deleteSync(recursive: true));
    final b = AppServices.create(AppDatabase.inMemory(), blobDirectory: bDir, syncApiFactory: api);
    for (final s in [a, b]) {
      s.sync.configure(url: 'http://sync.test', token: FakeBlobServer.token);
    }

    final bytes = Uint8List.fromList(utf8.encode('%PDF-1.7 big document'));
    final sha = await a.blobs.putBytes(bytes, mime: 'application/pdf');
    a.notebooks.create(
      title: 'PDF',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    await a.sync.syncNow();
    expect(a.sync.lastError, isNull);
    expect(server.log.take(3), ['HEAD $sha', 'PUT $sha', 'push']);
    expect(a.blobs.pendingUploads(), isEmpty);

    // Already uploaded: nothing is sent again.
    server.log.clear();
    await a.sync.syncNow();
    expect(server.log.where((l) => l.contains(sha)), isEmpty);

    expect(b.blobs.has(sha), isFalse);
    expect(await b.sync.fetchBlob(sha), isTrue);
    expect(await b.blobs.read(sha), bytes);
    expect(await b.sync.fetchBlob('0' * 64), isFalse); // Not on the server.
  });
}
