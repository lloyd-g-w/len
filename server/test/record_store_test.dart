import 'dart:io';

import 'package:len_sync_server/len_sync_server.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

SyncRecord rec(
  String id, {
  int updatedAt = 1000,
  String deviceId = 'dev-a',
  String collection = 'notes',
  bool deleted = false,
  Map<String, Object?>? data = const {'v': 1},
  RecordVersion? base,
}) => SyncRecord(
  collection: collection,
  id: id,
  updatedAt: updatedAt,
  deviceId: deviceId,
  deleted: deleted,
  data: data,
  base: base,
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

  test('a record keeps its base until a record without one replaces it', () {
    const base = RecordVersion(updatedAt: 900, deviceId: 'dev-b');
    store.push([rec('1', deleted: true, base: base)]);
    expect(only().base?.toJson(), base.toJson());
    expect(only().toJson()['base'], {'updatedAt': 900, 'deviceId': 'dev-b'});
    store.push([rec('1', updatedAt: 2000)]);
    expect(only().base, isNull);
    expect(only().toJson().containsKey('base'), isFalse);
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

    test('the payload cap counts UTF-8 bytes, not UTF-16 code units', () {
      final wide = RecordStore.inMemory();
      addTearDown(wide.close);
      // '€' is one UTF-16 code unit but three UTF-8 bytes: each payload is
      // {"t":"€€€€€€€€€€"} = 38 bytes (18 code units).
      wide.push([
        for (var i = 0; i < 3; i++) rec('$i', data: {'t': '€' * 10}),
      ]);
      final page = wide.pull(since: 0, limit: 5, maxDataBytes: 60);
      expect(page.records.map((r) => r.seq), [1, 2]);
      expect(page.hasMore, isTrue);
    });

    test('since at the end returns since', () {
      final page = store.pull(since: 5, limit: 5);
      expect(page.records, isEmpty);
      expect(page.nextSince, 5);
      expect(page.hasMore, isFalse);
    });

    test('since beyond the end means lost history: new server id', () {
      final id = store.serverId;
      expect(() => store.pull(since: 42, limit: 5), throwsA(isA<HistoryLostException>()));
      expect(store.serverId, isNot(id));
      expect(store.serverId, matches(RegExp(r'^[0-9a-f]{32}$')));
    });
  });

  test('persists to a file and reopens with schema intact', () async {
    final dir = await Directory.systemTemp.createTemp('len_store_test');
    final path = '${dir.path}/len.db';
    final a = RecordStore.open(path)..push([rec('1')]);
    final id = a.serverId;
    a.close();
    final b = RecordStore.open(path);
    expect(b.serverId, id, reason: 'the id survives restarts');
    expect(b.currentSeq(), 1);
    expect(b.pull(since: 0, limit: 10).records.single.id, '1');
    b.close();
    await dir.delete(recursive: true);
  });

  test('commits are durable: WAL with synchronous = FULL', () async {
    final dir = await Directory.systemTemp.createTemp('len_store_sync');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/len.db';
    final store = RecordStore.open(path);
    addTearDown(store.close);
    // RecordStore keeps its connection private; a pragma on another
    // connection would not tell, so read it through the store's own.
    expect(store.pragma('journal_mode'), 'wal');
    expect(store.pragma('synchronous'), 2); // FULL
  });

  test('creates the schema at user_version 2; reopening changes nothing', () async {
    final dir = await Directory.systemTemp.createTemp('len_store_schema');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/len.db';
    RecordStore.open(path).close();
    String schema(Database db) => db
        .select('SELECT type, name, sql FROM sqlite_master ORDER BY name')
        .map((r) => '${r['type']} ${r['name']} ${r['sql']}')
        .join('\n');
    final raw = sqlite3.open(path);
    expect(raw.userVersion, 2);
    expect(RecordStore.schemaVersion, 2);
    final before = schema(raw);
    expect(before, allOf(contains('table records'), contains('index records_seq')));
    expect(before, allOf(contains('table blob_gc'), contains('table meta')));
    raw.close();

    RecordStore.open(path).close();
    final again = sqlite3.open(path);
    expect(schema(again), before);
    expect(again.userVersion, 2);
    again.close();
  });

  test('a version 1 database gains record bases, keeping its records', () async {
    final dir = await Directory.systemTemp.createTemp('len_store_v1');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/len.db';
    sqlite3.open(path)
      ..execute('''
        CREATE TABLE records (collection TEXT NOT NULL, id TEXT NOT NULL,
          updated_at INTEGER NOT NULL, device_id TEXT NOT NULL, deleted INTEGER NOT NULL,
          data TEXT, seq INTEGER NOT NULL, PRIMARY KEY (collection, id))''')
      ..execute('CREATE UNIQUE INDEX records_seq ON records (seq)')
      ..execute(
        'CREATE TABLE blob_gc (sha256 TEXT PRIMARY KEY NOT NULL, '
        'unreferenced_since INTEGER NOT NULL) WITHOUT ROWID',
      )
      ..execute('CREATE TABLE meta (key TEXT PRIMARY KEY NOT NULL, value) WITHOUT ROWID')
      ..execute("INSERT INTO records VALUES ('notes', '1', 5, 'dev-a', 0, '{\"v\":1}', 1)")
      ..userVersion = 1
      ..close();
    final store = RecordStore.open(path);
    addTearDown(store.close);
    expect(store.pull(since: 0, limit: 10).records.single.data, {'v': 1});
    store.push([rec('2', deleted: true, base: const RecordVersion(updatedAt: 4, deviceId: 'b'))]);
    expect(store.pull(since: 1, limit: 10).records.single.base?.updatedAt, 4);
  });

  test('refuses a database from a newer server', () async {
    final dir = await Directory.systemTemp.createTemp('len_store_newer');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/len.db';
    sqlite3.open(path)
      ..userVersion = RecordStore.schemaVersion + 1
      ..close();
    expect(() => RecordStore.open(path), throwsA(isA<UnsupportedSchemaException>()));
  });
}
