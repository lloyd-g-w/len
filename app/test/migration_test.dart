import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/folder_repository.dart';
import 'package:len/data/notebook_repository.dart';
import 'package:len/data/page_repository.dart';
import 'package:len/data/stroke_codec.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/chunk_grid.dart';
import 'package:len/domain/cover_style.dart';
import 'package:len/domain/stroke.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'data_test.dart' show FakeClock;

/// Writes a database exactly as app schema v2 (v0.1, before pen styles and
/// library folders) left it, with one paged notebook holding one stroke and
/// one canvas notebook holding one stroke.
void _createV2Database(String path) {
  final db = sqlite3.open(path);
  db.execute('''
    CREATE TABLE notebooks (
      id TEXT PRIMARY KEY NOT NULL, title TEXT NOT NULL, kind TEXT NOT NULL,
      paper TEXT NOT NULL, cover_color INTEGER NOT NULL, created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL, device_id TEXT NOT NULL,
      deleted INTEGER NOT NULL DEFAULT 0, dirty INTEGER NOT NULL DEFAULT 1)''');
  db.execute('''
    CREATE TABLE pages (
      id TEXT PRIMARY KEY NOT NULL, notebook_id TEXT NOT NULL, sort_key REAL NOT NULL,
      width REAL NOT NULL, height REAL NOT NULL, paper TEXT NOT NULL,
      updated_at INTEGER NOT NULL, device_id TEXT NOT NULL,
      deleted INTEGER NOT NULL DEFAULT 0, dirty INTEGER NOT NULL DEFAULT 1)''');
  db.execute('CREATE INDEX pages_by_notebook ON pages(notebook_id, sort_key)');
  db.execute('''
    CREATE TABLE strokes (
      id TEXT PRIMARY KEY NOT NULL, surface_id TEXT NOT NULL, tool TEXT NOT NULL,
      color INTEGER NOT NULL, width REAL NOT NULL, points BLOB NOT NULL,
      created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, device_id TEXT NOT NULL,
      deleted INTEGER NOT NULL DEFAULT 0, dirty INTEGER NOT NULL DEFAULT 1)''');
  db.execute('CREATE INDEX strokes_by_surface ON strokes(surface_id)');
  db.execute('CREATE INDEX strokes_dirty ON strokes(id) WHERE dirty = 1');
  db.execute('''
    CREATE TABLE stroke_chunks (
      surface_id TEXT NOT NULL, cx INTEGER NOT NULL, cy INTEGER NOT NULL,
      stroke_id TEXT NOT NULL, PRIMARY KEY (surface_id, cx, cy, stroke_id)) WITHOUT ROWID''');
  db.execute('CREATE INDEX stroke_chunks_by_stroke ON stroke_chunks(stroke_id)');
  db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL)');

  db.execute(
    "INSERT INTO notebooks VALUES ('nb', 'Physics', 'paged', 'lined', 255, 10, 500, 'old', 0, 0)",
  );
  db.execute(
    "INSERT INTO notebooks VALUES ('cv', 'Ideas', 'canvas', 'dotted', 7, 20, 600, 'old', 0, 1)",
  );
  db.execute("INSERT INTO pages VALUES ('pg', 'nb', 1.0, 800, 1100, 'lined', 500, 'old', 0, 0)");
  final points = StrokeCodec.encode(const [StrokePoint(10, 10, 0.5), StrokePoint(60, 40, 0.5)]);
  for (final (id, surface) in [('s1', 'pg'), ('s2', 'cv')]) {
    db.execute('INSERT INTO strokes VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0)', [
      id,
      surface,
      'pen',
      0xFF000000,
      2.0,
      points,
      30,
      700,
      'old',
    ]);
    db.execute('INSERT INTO stroke_chunks VALUES (?, 0, 0, ?)', [surface, id]);
  }
  db.execute("INSERT INTO settings VALUES ('device_id', 'old')");
  db.execute('PRAGMA user_version = 2');
  db.dispose();
}

/// Column and index definitions of every table, to compare schemas.
Map<String, Object> _schemaOf(AppDatabase database) {
  final db = database.db;
  final tables = db
      .select("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")
      .map((r) => r['name'] as String);
  return {
    for (final t in tables)
      t: [
        for (final c in db.select('PRAGMA table_info($t)'))
          '${c['name']} ${c['type']} ${c['notnull']} ${c['dflt_value']} ${c['pk']}',
      ]..sort(),
    'indexes':
        db
            .select(
              "SELECT name, tbl_name FROM sqlite_master WHERE type = 'index' "
              "AND name NOT LIKE 'sqlite_autoindex%'",
            )
            .map((r) => '${r['tbl_name']}.${r['name']}')
            .toList()
          ..sort(),
    'version': db.select('PRAGMA user_version').first.columnAt(0) as int,
  };
}

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('len_migration_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('upgrading a v2 database matches a fresh install', () {
    final upgradedPath = p.join(dir.path, 'old.db');
    _createV2Database(upgradedPath);
    final upgraded = AppDatabase.open(upgradedPath);
    final fresh = AppDatabase.open(p.join(dir.path, 'fresh.db'));
    addTearDown(upgraded.close);
    addTearDown(fresh.close);

    expect(_schemaOf(upgraded), _schemaOf(fresh));
  });

  test('a v2 library works after upgrading: read, organise, duplicate, sync', () {
    final path = p.join(dir.path, 'old.db');
    _createV2Database(path);
    final database = AppDatabase.open(path);
    addTearDown(database.close);
    final clock = FakeClock()..now = 10000;
    final strokes = StrokeRepository(database, deviceId: 'new', clock: clock);
    final pages = PageRepository(database, deviceId: 'new', clock: clock);
    final notebooks = NotebookRepository(
      database,
      deviceId: 'new',
      pages: pages,
      strokes: strokes,
      clock: clock,
    );
    final folders = FolderRepository(database, deviceId: 'new', clock: clock);

    // Existing rows get the library defaults; "last edited" = last change.
    final physics = notebooks.get('nb')!;
    expect(physics.editedAt, 500);
    expect(physics.folderId, isNull);
    expect(physics.favorite, isFalse);
    expect(physics.isTrashed, isFalse);
    expect(physics.coverStyle, CoverStyle.plain);
    expect(notebooks.list().map((n) => n.id), ['cv', 'nb']);

    // Old strokes load with the legacy style.
    final range = ChunkGrid.rangeFor(const Rect.fromLTWH(0, 0, 100, 100));
    final old = strokes.loadChunks('pg', strokes.populatedChunks('pg', range)).single;
    expect(old.tool, InkTool.pen);
    expect(old.style, StrokeStyle.defaultsFor(InkTool.pen));

    // Library operations work on upgraded rows.
    final school = folders.create(name: 'School', color: 1);
    notebooks.moveTo('nb', school.id);
    notebooks.setFavorite('nb', true);
    expect(notebooks.get('nb')!.folderId, school.id);
    expect(notebooks.get('nb')!.editedAt, 500, reason: 'organising is not editing');

    final copy = notebooks.duplicate('nb')!;
    final copyPage = pages.pagesOf(copy.id).single;
    final copied = strokes.loadChunks(copyPage.id, strokes.populatedChunks(copyPage.id, range));
    expect(copied.single.points, old.points);

    folders.delete(school.id);
    notebooks.trashAllIn({school.id});
    expect(notebooks.trashed().map((n) => n.id), containsAll(['nb', copy.id]));
    notebooks.restore('nb');
    expect(notebooks.get('nb')!.folderId, isNull, reason: 'its folder is gone');

    // Upgraded rows sync with the new fields.
    final records = notebooks.dirtyRecords(100);
    final record = records.singleWhere((r) => r.id == 'nb');
    expect(record.data, containsPair('favorite', true));
    expect(record.data, containsPair('editedAt', 500));
    expect(record.data, containsPair('coverStyle', 'plain'));
  });

  test('reopening an up-to-date database changes nothing', () {
    final path = p.join(dir.path, 'old.db');
    _createV2Database(path);
    AppDatabase.open(path).close();
    final again = AppDatabase.open(path);
    addTearDown(again.close);
    expect(again.db.select('SELECT COUNT(*) AS c FROM notebooks').first['c'], 2);
  });
}
