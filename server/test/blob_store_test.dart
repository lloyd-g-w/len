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

  test('open removes leftover temp files', () {
    File('${blobs.root}/tmp/stale').writeAsStringSync('x');
    final reopened = BlobStore.open(blobs.root);
    expect(Directory('${reopened.root}/tmp').listSync(), isEmpty);
  });

  test('invalid sha throws ArgumentError', () {
    expect(() => blobs.has('nope'), throwsArgumentError);
  });
}
