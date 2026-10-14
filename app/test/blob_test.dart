import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:cross_file/cross_file.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/blob_backend.dart';
import 'package:len/data/blob_store.dart';
import 'package:len/domain/cancellation.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/waveform.dart';
import 'package:len/platform/blob_backend_native.dart';
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
    if (path == '/v1/health') {
      return http.Response(
        '{"status":"ok","protocol":1,"maxBlobBytes":1000000,"blobsCollectedAt":0,'
        '"serverId":"blob-server"}',
        200,
      );
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

  for (final (name, backend) in <(String, BlobBackend Function())>[
    ('files', () => FileBlobBackend(dir.path)),
    ('memory', MemoryBlobBackend.new),
  ]) {
    test('blob store is content addressed and idempotent ($name)', () async {
      final store = BlobStore(AppDatabase.inMemory(), backend());
      final bytes = Uint8List.fromList(utf8.encode('%PDF-1.4 hello'));
      final sha = await store.putBytes(bytes, mime: 'application/pdf');
      expect(sha, sha256.convert(bytes).toString());
      expect(await store.has(sha), isTrue);
      expect(await store.read(sha), bytes);
      expect(await collectBytes(store.openRead(sha)), bytes);
      expect(store.sizeOf(sha), bytes.length);
      expect(await store.putBytes(bytes, mime: 'application/pdf'), sha);
      expect(store.pendingUploads(), [sha]);

      expect(await store.putFile(XFile.fromData(bytes), mime: 'application/pdf'), sha);
      expect(
        await BlobStore.hashStream(Stream.fromIterable([bytes.sublist(0, 3), bytes.sublist(3)])),
        sha,
      );

      store.markUploaded(sha);
      expect(store.pendingUploads(), isEmpty);
      store.markAllNotUploaded();
      expect(store.pendingUploads(), [sha]);
      expect(await store.has('../../etc/passwd'), isFalse);
      expect(() => store.localPath('../../etc/passwd'), throwsArgumentError);
    });
  }

  test('file backend: blobs are files, picked files are streamed in', () async {
    final store = BlobStore(AppDatabase.inMemory(), FileBlobBackend(dir.path));
    final bytes = Uint8List.fromList(List.generate(200000, (i) => i % 251));
    final source = File('${dir.path}/in.pdf')..writeAsBytesSync(bytes);
    final sha = await store.putFile(XFile(source.path), mime: 'application/pdf');
    expect(sha, sha256.convert(bytes).toString());
    expect(store.localPath(sha), endsWith('${sha.substring(0, 2)}/$sha'));
    expect(File(store.localPath(sha)!).readAsBytesSync(), bytes);
    expect(dir.listSync(recursive: true).where((f) => f.path.endsWith('.tmp')), isEmpty);
  });

  test('a cancelled putFile stores nothing; cancelled imports discard their blob', () async {
    final store = BlobStore(AppDatabase.inMemory(), MemoryBlobBackend());
    final bytes = Uint8List.fromList(utf8.encode('%PDF-1.4 cancel me'));
    final token = CancellationToken()..cancel();
    await expectLater(
      store.putFile(XFile.fromData(bytes), mime: 'application/pdf', cancel: token),
      throwsA(isA<Cancelled>()),
    );
    expect(store.pendingUploads(), isEmpty);

    final sha = await store.putFile(XFile.fromData(bytes), mime: 'application/pdf');
    await store.discardIfUnreferenced(sha, () => {sha}); // Still used: kept.
    expect(await store.has(sha), isTrue);
    await store.discardIfUnreferenced(sha, () => {});
    expect(await store.has(sha), isFalse);
    expect(store.pendingUploads(), isEmpty);
  });

  test('downloaded blobs are verified', () async {
    final store = BlobStore(AppDatabase.inMemory(), MemoryBlobBackend());
    final bytes = Uint8List.fromList([1, 2, 3]);
    final sha = sha256.convert(bytes).toString();
    await expectLater(store.putDownloaded(sha, Uint8List.fromList([9])), throwsFormatException);
    expect(await store.has(sha), isFalse);
    await store.putDownloaded(sha, bytes);
    expect(await store.has(sha), isTrue);
    expect(store.pendingUploads(), isEmpty); // The server has it.
  });

  test('downloaded blobs keep the type of their content', () async {
    final store = BlobStore(AppDatabase.inMemory(), MemoryBlobBackend());
    final kinds = {
      'application/pdf': '%PDF-1.7\n'.codeUnits,
      'image/png': [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
      'image/jpeg': [0xFF, 0xD8, 0xFF, 0xE0],
      'audio/aac': [0xFF, 0xF1, 0x50, 0x80],
      'audio/mp4': [0, 0, 0, 0x20, ...'ftypM4A '.codeUnits],
      Waveform.mime: [0x4C, 0x57, 1, 10, 0, 0],
    };
    for (final MapEntry(key: mime, value: data) in kinds.entries) {
      final bytes = Uint8List.fromList(data);
      final sha = sha256.convert(bytes).toString();
      await store.putDownloaded(sha, bytes);
      expect(store.mimeOf(sha), mime);
    }
  });

  test('sync uploads blobs before records; other devices fetch lazily', () async {
    final server = FakeBlobServer();
    SyncApi api(String url, String token) =>
        SyncApi(baseUrl: url, token: token, client: server.client);
    final a = AppServices.create(
      AppDatabase.inMemory(),
      blobBackend: FileBlobBackend(dir.path),
      syncApiFactory: api,
    );
    final b = AppServices.create(AppDatabase.inMemory(), syncApiFactory: api);
    for (final s in [a, b]) {
      s.sync.configure(url: 'http://sync.test', token: FakeBlobServer.token);
    }

    final bytes = Uint8List.fromList(utf8.encode('%PDF-1.7 big document'));
    final sha = await a.blobs.putBytes(bytes, mime: 'application/pdf');
    final notebook = a.notebooks.create(
      title: 'PDF',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    a.pages.insertPages(notebook.id, [
      (
        size: const Size(100, 140),
        paper: Paper(PaperStyle.blank),
        color: PaperColor.white,
        background: PageBackground.pdf(blob: sha, pageIndex: 0),
      ),
    ]);
    await a.sync.syncNow();
    expect(a.sync.lastError, isNull);
    expect(server.log.take(3), ['HEAD $sha', 'PUT $sha', 'push']);
    expect(server.blobs[sha], bytes);
    expect(a.blobs.pendingUploads(), isEmpty);

    // Already uploaded: nothing is sent again.
    server.log.clear();
    await a.sync.syncNow();
    expect(server.log.where((l) => l.contains(sha)), isEmpty);

    expect(await b.blobs.has(sha), isFalse);
    expect(await b.sync.fetchBlob(sha), isTrue);
    expect(await b.blobs.read(sha), bytes);
    expect(await b.sync.fetchBlob('0' * 64), isFalse); // Not on the server.
  });
}
