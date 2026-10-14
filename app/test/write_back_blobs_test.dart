import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/blob_backend.dart';
import 'package:len/data/write_back.dart';
import 'package:len/data/write_back_blobs.dart';

/// A blob store that can be full.
class _FullableBackend extends MemoryBlobBackend {
  bool full = false;

  /// Blobs that don't fit (when not [full]).
  final Set<String> refused = {};

  @override
  Future<void> write(String sha, Stream<List<int>> data) async {
    if (full || refused.contains(sha)) throw const StorageFullException();
    await super.write(sha, data);
  }
}

void main() {
  final bytes = Uint8List.fromList([1, 2, 3]);

  test('a blob the storage refused stays readable and is stored later', () async {
    final inner = _FullableBackend()..full = true;
    final blobs = WriteBackBlobBackend(inner);
    await blobs.write('a', Stream.value(bytes)); // No exception: kept.
    expect(blobs.failure, WriteFailure.full);
    expect(blobs.pending, isTrue);
    expect(await blobs.read('a'), bytes);
    expect(await blobs.contains('a'), isTrue);
    expect(await blobs.openRead('a').first, bytes);
    expect(await inner.contains('a'), isFalse);
    expect(await blobs.flush(), isFalse);

    inner.full = false;
    expect(await blobs.flush(), isTrue);
    expect(blobs.failure, isNull);
    expect(blobs.pending, isFalse);
    expect(await inner.read('a'), bytes);
  });

  test('a blob stored after one the storage refused leaves that one retried', () {
    fakeAsync((async) {
      final inner = _FullableBackend()..refused.add('big');
      final blobs = WriteBackBlobBackend(inner);
      unawaited(blobs.write('big', Stream.value(bytes)));
      async.flushMicrotasks();
      expect(blobs.failure, WriteFailure.full);
      // A small file still fits.
      unawaited(blobs.write('small', Stream.value(bytes)));
      async.flushMicrotasks();
      expect(blobs.pending, isTrue);
      expect(blobs.failure, WriteFailure.full);

      inner.refused.clear(); // Space freed: the retry stores it.
      async.elapse(const Duration(minutes: 1));
      expect(blobs.pending, isFalse);
      expect(blobs.failure, isNull);
    });
  });

  test('deleting an unstored blob drops it and the failure', () async {
    final inner = _FullableBackend()..full = true;
    final blobs = WriteBackBlobBackend(inner);
    await blobs.write('a', Stream.value(bytes));
    await blobs.delete('a');
    expect(blobs.pending, isFalse);
    expect(blobs.failure, isNull);
    expect(await blobs.contains('a'), isFalse);
  });

  test('close stores what is pending and rejects later writes', () async {
    final inner = _FullableBackend()..full = true;
    final blobs = WriteBackBlobBackend(inner);
    await blobs.write('a', Stream.value(bytes));
    inner.full = false;
    expect(await blobs.close(), isTrue);
    expect(await inner.contains('a'), isTrue);
    expect(() => blobs.write('b', Stream.value(bytes)), throwsStateError);
  });

  test('StorageWrites sums up its stores', () async {
    final inner = _FullableBackend()..full = true;
    final blobs = WriteBackBlobBackend(inner);
    final writes = StorageWrites()..add(blobs);
    var changes = 0;
    writes.addListener(() => changes++);
    await blobs.write('a', Stream.value(bytes));
    expect(writes.pending, isTrue);
    expect(writes.failure, WriteFailure.full);
    expect(changes, greaterThan(0));
    inner.full = false;
    expect(await writes.flush(), isTrue);
    expect(writes.failure, isNull);
    expect(writes.pending, isFalse);
  });
}
