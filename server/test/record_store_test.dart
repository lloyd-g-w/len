import 'dart:io';

import 'package:len_sync_server/len_sync_server.dart';
import 'package:test/test.dart';

SyncRecord rec(
  String id, {
  int updatedAt = 1000,
  String deviceId = 'dev-a',
  String collection = 'notes',
  bool deleted = false,
  Map<String, Object?>? data = const {'v': 1},
}) => SyncRecord(
  collection: collection,
  id: id,
  updatedAt: updatedAt,
  deviceId: deviceId,
  deleted: deleted,
  data: data,
);

void main() {
  late RecordStore store;

  setUp(() => store = RecordStore.inMemory());
  tearDown(() => store.close());

  SyncRecord only() {
    final page = store.pull(since: 0, limit: 10);
    expect(page.records, hasLength(1));
    return page.records.single;
  }

  test('empty store has seq 0 and empty pull', () {
    expect(store.currentSeq(), 0);
    final page = store.pull(since: 0, limit: 10);
    expect(page.records, isEmpty);
    expect(page.nextSince, 0);
    expect(page.hasMore, isFalse);
  });

  test('stores new records and assigns increasing seqs', () {
    final result = store.push([rec('1'), rec('2'), rec('3')]);
    expect(result.applied, 3);
    expect(result.ignored, 0);
    expect(result.serverSeq, 3);
    final page = store.pull(since: 0, limit: 10);
    expect(page.records.map((r) => r.seq), [1, 2, 3]);
    expect(page.records.map((r) => r.id), ['1', '2', '3']);
    expect(page.records.first.data, {'v': 1});
  });

  test('same id in different collections are distinct', () {
    final result = store.push([rec('1'), rec('1', collection: 'pages')]);
    expect(result.applied, 2);
  });

  test('newer record wins and gets a new seq', () {
    store.push([rec('1', updatedAt: 1000), rec('2')]);
    final result = store.push([
      rec('1', updatedAt: 2000, data: {'v': 2}),
    ]);
    expect(result.applied, 1);
    expect(result.serverSeq, 3);
    final page = store.pull(since: 0, limit: 10);
    expect(page.records.map((r) => r.id), ['2', '1']);
    expect(page.records.last.seq, 3);
    expect(page.records.last.data, {'v': 2});
    expect(page.records.last.updatedAt, 2000);
  });

  test('older record is ignored and seq does not change', () {
    store.push([rec('1', updatedAt: 2000)]);
    final result = store.push([
      rec('1', updatedAt: 1000, data: {'v': 9}),
    ]);
    expect(result.applied, 0);
    expect(result.ignored, 1);
    expect(result.serverSeq, 1);
    expect(only().data, {'v': 1});
  });

  test('identical record (echo) is ignored', () {
    store.push([rec('1')]);
    final result = store.push([rec('1')]);
    expect(result.ignored, 1);
    expect(store.currentSeq(), 1);
  });

  test('equal updatedAt is broken by larger deviceId', () {
    store.push([rec('1', deviceId: 'dev-b')]);
    expect(store.push([rec('1', deviceId: 'dev-a')]).applied, 0);
    expect(only().deviceId, 'dev-b');
    expect(store.push([rec('1', deviceId: 'dev-c')]).applied, 1);
    expect(only().deviceId, 'dev-c');
    expect(only().seq, 2);
  });

  test('tombstone replaces record with null data', () {
    store.push([rec('1', updatedAt: 1000)]);
    store.push([rec('1', updatedAt: 2000, deleted: true)]);
    final r = only();
    expect(r.deleted, isTrue);
    expect(r.data, isNull);
  });

  test('duplicates within one push follow LWW in order', () {
    final result = store.push([
      rec('1', updatedAt: 1000),
      rec('1', updatedAt: 3000, data: {'v': 3}),
      rec('1', updatedAt: 2000, data: {'v': 2}),
    ]);
    expect(result.applied, 2);
    expect(result.ignored, 1);
    expect(only().data, {'v': 3});
    expect(only().seq, 2);
  });

  group('pull pagination', () {
    setUp(() => store.push([for (var i = 0; i < 5; i++) rec('$i')]));

    test('pages with hasMore and nextSince', () {
      var page = store.pull(since: 0, limit: 2);
      expect(page.records.map((r) => r.seq), [1, 2]);
      expect(page.nextSince, 2);
      expect(page.hasMore, isTrue);

      page = store.pull(since: page.nextSince, limit: 2);
      expect(page.records.map((r) => r.seq), [3, 4]);
      expect(page.hasMore, isTrue);

      page = store.pull(since: page.nextSince, limit: 2);
      expect(page.records.map((r) => r.seq), [5]);
      expect(page.nextSince, 5);
      expect(page.hasMore, isFalse);
    });

    test('exact page boundary reports no more', () {
      final page = store.pull(since: 0, limit: 5);
      expect(page.records, hasLength(5));
      expect(page.hasMore, isFalse);
    });

    test('large payloads cut a page short but always return one', () {
      final page = store.pull(since: 0, limit: 5, maxDataBytes: 1);
      expect(page.records.map((r) => r.seq), [1]);
      expect(page.hasMore, isTrue);

      final rest = store.pull(since: 0, limit: 5, maxDataBytes: 1 << 20);
      expect(rest.records, hasLength(5));
      expect(rest.hasMore, isFalse);
    });

    test('since beyond end returns since', () {
      final page = store.pull(since: 42, limit: 5);
      expect(page.records, isEmpty);
      expect(page.nextSince, 42);
      expect(page.hasMore, isFalse);
    });
  });

  test('persists to a file and reopens with schema intact', () async {
    final dir = await Directory.systemTemp.createTemp('len_store_test');
    final path = '${dir.path}/len.db';
    final a = RecordStore.open(path)..push([rec('1')]);
    a.close();
    final b = RecordStore.open(path);
    expect(b.currentSeq(), 1);
    expect(b.pull(since: 0, limit: 10).records.single.id, '1');
    b.close();
    await dir.delete(recursive: true);
  });
}
