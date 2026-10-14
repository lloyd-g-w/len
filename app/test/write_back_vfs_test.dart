import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/write_back.dart';
import 'package:len/platform/write_back_vfs.dart';
import 'package:sqlite3/sqlite3.dart';

/// Stores files like IndexedDB would (blocks, atomic commits), and can be
/// made to fail like a full browser storage.
class _FakeStore implements BlockStore {
  final Map<String, Uint8List> files = {};
  Object? failWith;
  int commits = 0;
  bool closed = false;

  @override
  Future<Map<String, Uint8List>> readAll() async => {
    for (final e in files.entries) e.key: Uint8List.fromList(e.value),
  };

  @override
  Future<void> commit(List<FileChange> changes) async {
    await Future<void>.delayed(Duration.zero); // Asynchronous, like IndexedDB.
    if (failWith case final error?) throw error;
    commits++;
    for (final change in changes) {
      if (change.deleted) {
        files.remove(change.path);
        continue;
      }
      final length = change.length!;
      final old = change.replace ? Uint8List(0) : files[change.path] ?? Uint8List(0);
      final file = Uint8List(length)..setRange(0, min(length, old.length), old);
      for (final MapEntry(key: offset, value: block) in change.blocks.entries) {
        file.setRange(offset, min(length, offset + block.length), block);
      }
      files[change.path] = file;
    }
  }

  @override
  void close() => closed = true;
}

var _vfsCount = 0;

/// Opens a database on a [WriteBackFileSystem] over [store].
Future<(Database, WriteBackFileSystem)> _open(_FakeStore store) async {
  final fs = await WriteBackFileSystem.open(store, name: 'write-back-${_vfsCount++}');
  sqlite3.registerVirtualFileSystem(fs);
  addTearDown(() => sqlite3.unregisterVirtualFileSystem(fs));
  final db = sqlite3.open('/len.db', vfs: fs.name);
  addTearDown(() {
    try {
      db.close();
    } on Object catch (_) {}
  });
  return (db, fs);
}

List<String> _notes(Database db) => [
  for (final row in db.select('SELECT body FROM notes ORDER BY id')) row['body'] as String,
];

/// Reopens [store] as a fresh tab would and checks the database.
Future<List<String>> _reopened(_FakeStore store) async {
  final (db, _) = await _open(store);
  expect(db.select('PRAGMA integrity_check').single.values.single, 'ok');
  return _notes(db);
}

void main() {
  late _FakeStore store;
  setUp(() => store = _FakeStore());

  Future<Database> created() async {
    final (db, fs) = await _open(store);
    db.execute('CREATE TABLE notes (id INTEGER PRIMARY KEY, body TEXT)');
    expect(await fs.flush(), isTrue);
    return db;
  }

  test('reads copy just the range asked for, short at the end', () {
    final file = Uint8List.fromList(List.generate(10000, (i) => i % 251));
    final page = Uint8List(4096);
    expect(readFileRange(file, page, 4096), 4096);
    expect(page, file.sublist(4096, 8192));
    expect(readFileRange(file, page, 8192), 10000 - 8192);
    expect(page.sublist(0, 10000 - 8192), file.sublist(8192));
    expect(readFileRange(file, page, 10000), 0);
  });

  test('changes reach the store right after each transaction', () async {
    final db = await created();
    db.execute("INSERT INTO notes (body) VALUES ('a')");
    await pumpEventQueue();
    expect(await _reopened(store), ['a']);
  });

  test('failed writes: usable in memory, reported, retried without loss', () async {
    final (db, fs) = await _open(store);
    db.execute('CREATE TABLE notes (id INTEGER PRIMARY KEY, body TEXT)');
    expect(await fs.flush(), isTrue);

    store.failWith = const StorageFullException();
    db.execute("INSERT INTO notes (body) VALUES ('one')");
    expect(await fs.flush(), isFalse);
    expect(fs.failure, WriteFailure.full);
    expect(fs.pending, isTrue);
    // Still usable: more changes, including growing the file.
    db.execute("INSERT INTO notes (body) VALUES ('two')");
    db.execute("INSERT INTO notes (body) VALUES ('${'x' * 20000}')");
    expect(_notes(db), hasLength(3));
    expect(await fs.flush(), isFalse);
    expect(await _reopened(store), isEmpty); // Nothing half-written.

    store.failWith = null; // Space freed.
    expect(await fs.flush(), isTrue);
    expect(fs.failure, isNull);
    expect(fs.pending, isFalse);
    expect(await _reopened(store), ['one', 'two', 'x' * 20000]);
  });

  test('other errors are reported as failed', () async {
    final (db, fs) = await _open(store);
    store.failWith = StateError('broken');
    db.execute('CREATE TABLE notes (id INTEGER PRIMARY KEY, body TEXT)');
    expect(await fs.flush(), isFalse);
    expect(fs.failure, WriteFailure.failed);
  });

  test('never stores the middle of a transaction', () async {
    final (db, fs) = await _open(store);
    db.execute('CREATE TABLE notes (id INTEGER PRIMARY KEY, body TEXT)');
    expect(await fs.flush(), isTrue);
    db.execute('PRAGMA cache_size = 10'); // Spills pages to the file before COMMIT.
    db.execute('BEGIN');
    for (var i = 0; i < 200; i++) {
      db.execute("INSERT INTO notes (body) VALUES ('${'n' * 2000}')");
    }
    expect(await fs.flush(), isFalse);
    expect(await _reopened(store), isEmpty);
    db.execute('COMMIT');
    await pumpEventQueue();
    expect(fs.pending, isFalse);
    expect(await _reopened(store), hasLength(200));
  });

  test('shrinking the file (VACUUM) is stored', () async {
    final (db, fs) = await _open(store);
    db.execute('CREATE TABLE notes (id INTEGER PRIMARY KEY, body TEXT)');
    for (var i = 0; i < 50; i++) {
      db.execute("INSERT INTO notes (body) VALUES ('${'n' * 4000}')");
    }
    db.execute('DELETE FROM notes WHERE id > 1');
    expect(await fs.flush(), isTrue);
    final before = store.files['/len.db']!.length;
    db.execute('VACUUM');
    expect(await fs.flush(), isTrue);
    expect(store.files['/len.db']!.length, lessThan(before));
    expect(await _reopened(store), hasLength(1));
  });

  test('random failures never lose or corrupt data', () async {
    final random = Random(7);
    final (db, fs) = await _open(store);
    db.execute('CREATE TABLE notes (id INTEGER PRIMARY KEY, body TEXT)');
    final expected = <String>[];
    for (var i = 0; i < 60; i++) {
      store.failWith = random.nextInt(3) == 0 ? const StorageFullException() : null;
      final body = 'note $i ${'z' * random.nextInt(6000)}';
      db.execute('INSERT INTO notes (body) VALUES (?)', [body]);
      expected.add(body);
      if (random.nextBool()) {
        db.execute('DELETE FROM notes WHERE id = (SELECT min(id) FROM notes)');
        expected.removeAt(0);
      }
      if (random.nextBool()) await fs.flush();
      if (store.failWith == null && !fs.pending) {
        expect(await _reopened(store), expected);
      }
    }
    store.failWith = null;
    expect(await fs.flush(), isTrue);
    expect(await _reopened(store), expected);
  });

  test('close stores everything, then rejects writes', () async {
    final (db, fs) = await _open(store);
    db.execute('CREATE TABLE notes (id INTEGER PRIMARY KEY, body TEXT)');
    db.execute("INSERT INTO notes (body) VALUES ('last')");
    expect(await fs.close(), isTrue);
    expect(store.closed, isTrue);
    expect(() => db.execute("INSERT INTO notes (body) VALUES ('late')"), throwsA(anything));
    expect(await _reopened(store), ['last']);
  });

  test('close while storage is full keeps retrying until stored', () async {
    final (db, fs) = await _open(store);
    db.execute('CREATE TABLE notes (id INTEGER PRIMARY KEY, body TEXT)');
    store.failWith = const StorageFullException();
    expect(await fs.close(), isFalse);
    expect(fs.pending, isTrue);
    store.failWith = null;
    expect(await fs.flush(), isTrue);
    expect(fs.pending, isFalse);
    expect(store.files, contains('/len.db'));
  });
}
