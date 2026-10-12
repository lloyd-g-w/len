import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:len_sync_server/len_sync_server.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late BlobStore blobs;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('len_blob_store_test_');
    blobs = BlobStore.open('${dir.path}/blobs');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  final data = utf8.encode('hello blob');
  final sha = sha256.convert(data).toString();

  Stream<List<int>> chunks(List<int> bytes, {int size = 3}) => Stream.fromIterable([
    for (var i = 0; i < bytes.length; i += size)
      bytes.sublist(i, i + size > bytes.length ? bytes.length : i + size),
  ]);

  List<FileSystemEntity> tmpFiles() => Directory('${blobs.root}/tmp').listSync();

  test('isValidSha', () {
    expect(BlobStore.isValidSha(sha), isTrue);
    expect(BlobStore.isValidSha(sha.toUpperCase()), isFalse);
    expect(BlobStore.isValidSha(sha.substring(1)), isFalse);
    expect(BlobStore.isValidSha('${sha}0'), isFalse);
    expect(BlobStore.isValidSha('g' * 64), isFalse);
  });

  test('put stores under <first 2 hex>/<sha> and reads back', () async {
    expect(blobs.has(sha), isFalse);
    expect(blobs.size(sha), isNull);
    final size = await blobs.put(sha, chunks(data), maxBytes: 100);
    expect(size, data.length);
    expect(blobs.has(sha), isTrue);
    expect(blobs.size(sha), data.length);
    expect(blobs.pathFor(sha), '${blobs.root}/${sha.substring(0, 2)}/$sha');
    expect(File(blobs.pathFor(sha)).readAsBytesSync(), data);
    expect(await blobs.openRead(sha).expand((c) => c).toList(), data);
    expect(tmpFiles(), isEmpty);
  });

  test('put syncs the new shard directory and the renamed entry to disk', () async {
    final synced = <String>[];
    final store = BlobStore.open(
      '${dir.path}/synced',
      syncDirectory: (path) {
        // Each sync happens once the entry it makes durable exists.
        if (path.endsWith('/${sha.substring(0, 2)}')) {
          expect(File('$path/$sha').existsSync(), isTrue);
        }
        synced.add(path);
      },
    );
    await store.put(sha, chunks(data), maxBytes: 100);
    final shard = '${store.root}/${sha.substring(0, 2)}';
    expect(synced, [store.root, shard]);
    expect(File(store.pathFor(sha)).readAsBytesSync(), data);
  });

  test('syncDirectory flushes a real directory and rejects a missing one', () {
    syncDirectory(dir.path);
    expect(() => syncDirectory('${dir.path}/missing'), throwsA(isA<FileSystemException>()));
  });

  test('put of an existing blob is a no-op', () async {
    await blobs.put(sha, chunks(data), maxBytes: 100);
    final size = await blobs.put(sha, Stream.error(StateError('not read')), maxBytes: 100);
    expect(size, data.length);
  });

  test('hash mismatch stores nothing', () async {
    final other = sha256.convert([1, 2, 3]).toString();
    await expectLater(
      blobs.put(other, chunks(data), maxBytes: 100),
      throwsA(isA<BlobHashMismatchException>()),
    );
    expect(blobs.has(other), isFalse);
    expect(tmpFiles(), isEmpty);
  });

  test('too large stores nothing', () async {
    await expectLater(
      blobs.put(sha, chunks(data), maxBytes: data.length - 1),
      throwsA(isA<BlobTooLargeException>()),
    );
    expect(blobs.has(sha), isFalse);
    expect(tmpFiles(), isEmpty);
  });

  test('aborted upload (stream error) stores nothing and removes the temp file', () async {
    final aborted =
        (StreamController<List<int>>()
              ..add(data.sublist(0, 3))
              ..addError(const SocketException('reset'))
              ..close())
            .stream;
    await expectLater(blobs.put(sha, aborted, maxBytes: 100), throwsA(isA<SocketException>()));
    expect(blobs.has(sha), isFalse);
    expect(tmpFiles(), isEmpty);
  });

  test('exactly maxBytes is accepted', () async {
    expect(await blobs.put(sha, chunks(data), maxBytes: data.length), data.length);
  });

  test('concurrent puts of the same blob are safe', () async {
    final sizes = await Future.wait([
      for (var i = 0; i < 8; i++) blobs.put(sha, chunks(data, size: 1), maxBytes: 100),
    ]);
    expect(sizes, everyElement(data.length));
    expect(File(blobs.pathFor(sha)).readAsBytesSync(), data);
    expect(tmpFiles(), isEmpty);
  });

  test('open removes only stale temp files (another instance may be uploading)', () {
    final stale = File('${blobs.root}/tmp/stale')..writeAsStringSync('x');
    stale.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 2)));
    final fresh = File('${blobs.root}/tmp/fresh')..writeAsStringSync('y');
    final reopened = BlobStore.open(blobs.root);
    expect(stale.existsSync(), isFalse);
    expect(fresh.existsSync(), isTrue);
    expect(reopened.removeStaleTmpFiles(Duration.zero), 1);
    expect(fresh.existsSync(), isFalse);
  });

  test('a stalled upload is abandoned after the idle timeout', () async {
    final stalled = StreamController<List<int>>();
    stalled.add(data.sublist(0, 3)); // ...and then nothing.
    await expectLater(
      blobs.put(sha, stalled.stream, maxBytes: 100, idleTimeout: const Duration(milliseconds: 50)),
      throwsA(isA<BlobUploadStalledException>()),
    );
    expect(blobs.has(sha), isFalse);
    expect(tmpFiles(), isEmpty);
    await stalled.close();
  });

  test('a slow but steady upload is not timed out', () async {
    Stream<List<int>> slow() async* {
      for (final b in data) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        yield [b];
      }
    }

    final size = await blobs.put(
      sha,
      slow(),
      maxBytes: 100,
      idleTimeout: const Duration(milliseconds: 60),
    );
    expect(size, data.length);
  });

  test('re-putting an existing blob refreshes its modification time', () async {
    await blobs.put(sha, chunks(data), maxBytes: 100);
    final file = File(blobs.pathFor(sha));
    final old = DateTime.now().subtract(const Duration(days: 40));
    file.setLastModifiedSync(old);
    await blobs.put(sha, chunks(data), maxBytes: 100);
    expect(file.lastModifiedSync().isAfter(old.add(const Duration(days: 39))), isTrue);
  });

  test('invalid sha throws ArgumentError', () {
    expect(() => blobs.has('nope'), throwsArgumentError);
  });
}
