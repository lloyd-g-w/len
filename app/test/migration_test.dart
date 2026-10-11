import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/folder_repository.dart';
import 'package:len/data/notebook_repository.dart';
import 'package:len/data/page_repository.dart';
import 'package:len/data/search/search_index.dart';
import 'package:len/data/search/search_query.dart';
import 'package:len/data/search/search_schema.dart';
import 'package:len/data/stroke_codec.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/domain/chunk_grid.dart';
import 'package:len/domain/cover_style.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/common.dart';
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
  db.close();
}

/// [sql] with runs of whitespace collapsed (and none around parentheses
/// and commas), so formatting differences between hand-written and
/// migrated schemas do not matter.
String _normalizeSql(Object? sql) => (sql as String? ?? '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAll(RegExp(r'\s*([(),;])\s*'), r'$1')
    .trim();

/// Columns of every table (including virtual and FTS shadow tables), plus
/// the definitions (`sql`) of indexes, triggers and virtual tables, to
/// compare schemas.
Map<String, Object> _schemaOf(AppDatabase database) {
  final db = database.db;
  final tables = db
      .select("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")
      .map((r) => r['name'] as String);
  List<String> definitions(String where) =>
      db
          .select('SELECT type, name, tbl_name, sql FROM sqlite_master WHERE $where')
          .map((r) => '${r['type']} ${r['tbl_name']}.${r['name']}: ${_normalizeSql(r['sql'])}')
          .toList()
        ..sort();
  return {
    for (final t in tables)
      t: [
        for (final c in db.select('PRAGMA table_info("$t")'))
          '${c['name']} ${c['type']} ${c['notnull']} ${c['dflt_value']} ${c['pk']}',
      ]..sort(),
    'indexes': definitions("type = 'index' AND name NOT LIKE 'sqlite_autoindex%'"),
    'triggers': definitions("type = 'trigger'"),
    'virtual tables': definitions("type = 'table' AND sql LIKE 'CREATE VIRTUAL TABLE%'"),
    'version': db.select('PRAGMA user_version').first.columnAt(0) as int,
  };
}

/// Every row of every table of [db] (besides FTS internals), to check that
/// reopening changes nothing.
Map<String, List<String>> _contentsOf(CommonDatabase db) {
  final tables = db
      .select(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' "
        "AND name NOT LIKE 'search_fts%' ORDER BY name",
      )
      .map((r) => r['name'] as String);
  return {
    for (final t in tables) t: [for (final r in db.select('SELECT * FROM "$t"')) '$r']..sort(),
  };
}

/// Columns of [table] in [db] (empty if the table does not exist).
Set<String> _columns(CommonDatabase db, String table) =>
    db.select('PRAGMA table_info($table)').map((r) => r['name'] as String).toSet();

/// Inserts [row] into [table], keeping only the columns that exist at the
/// database's current schema version. Does nothing if the table is missing.
void _insertKnown(CommonDatabase db, String table, Map<String, Object?> row) {
  final columns = _columns(db, table);
  if (columns.isEmpty) return;
  final known = {
    for (final e in row.entries)
      if (columns.contains(e.key)) e.key: e.value,
  };
  db.execute(
    'INSERT INTO $table (${known.keys.join(', ')}) '
    'VALUES (${List.filled(known.length, '?').join(', ')})',
    known.values.toList(),
  );
}

final _seedPoints = StrokeCodec.encode(const [StrokePoint(10, 10, 0.5), StrokePoint(60, 40, 0.5)]);

/// Seeds a database at an old schema version with a folder, a paged
/// notebook (one page, one stroke, one text box), a canvas notebook (one
/// stroke) — each only as far as the tables and columns exist.
void _seedOldDatabase(CommonDatabase db) {
  const bookkeeping = {'updated_at': 500, 'device_id': 'old', 'deleted': 0, 'dirty': 0};
  _insertKnown(db, 'settings', {'key': 'device_id', 'value': 'old'});
  _insertKnown(db, 'folders', {
    ...bookkeeping,
    'id': 'fd',
    'name': 'Lectures',
    'parent_id': null,
    'color': 3,
    'created_at': 5,
  });
  for (final (id, title, kind) in [('nb', 'Physics', 'paged'), ('cv', 'Ideas', 'canvas')]) {
    _insertKnown(db, 'notebooks', {
      ...bookkeeping,
      'id': id,
      'title': title,
      'kind': kind,
      'paper': 'lined',
      'cover_color': 255,
      'created_at': 10,
      'folder_id': id == 'nb' ? 'fd' : null,
      'favorite': id == 'nb' ? 1 : 0,
      'cover_style': 'plain',
      'edited_at': 400,
      'paper_color': 'cream',
    });
  }
  _insertKnown(db, 'pages', {
    ...bookkeeping,
    'id': 'pg',
    'notebook_id': 'nb',
    'sort_key': 1.0,
    'width': 800,
    'height': 1100,
    'paper': 'lined',
    'paper_color': 'grey',
    'bookmarked': 1,
  });
  for (final (id, surface) in [('s1', 'pg'), ('s2', 'cv')]) {
    _insertKnown(db, 'strokes', {
      ...bookkeeping,
      'id': id,
      'surface_id': surface,
      'tool': 'pen',
      'color': 0xFF000000,
      'width': 2.0,
      'points': _seedPoints,
      'created_at': 30,
    });
    _insertKnown(db, 'stroke_chunks', {'surface_id': surface, 'cx': 0, 'cy': 0, 'stroke_id': id});
  }
  _insertKnown(db, 'elements', {
    ...bookkeeping,
    'id': 'el',
    'surface_id': 'pg',
    'type': 'text',
    'x': 10.0,
    'y': 20.0,
    'w': 100.0,
    'h': 30.0,
    'data': '{"text":"Quantum notes"}',
    'created_at': 40,
  });
  _insertKnown(db, 'element_chunks', {'surface_id': 'pg', 'cx': 0, 'cy': 0, 'element_id': 'el'});
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

  test('the test hook builds the latest schema like a normal open', () {
    final raw = sqlite3.openInMemory();
    AppDatabase.migrateForTest(raw, AppDatabase.latestVersion);
    final viaHook = AppDatabase.fromConnection(raw);
    final fresh = AppDatabase.inMemory();
    addTearDown(viaHook.close);
    addTearDown(fresh.close);
    expect(_schemaOf(viaHook), _schemaOf(fresh));
    expect(_schemaOf(fresh)['version'], AppDatabase.latestVersion);
    expect(SearchSchema.hasFts(fresh.db), isTrue, reason: 'FTS5 is bundled, so search_fts exists');
    expect(
      (_schemaOf(fresh)['triggers']! as List).length,
      greaterThanOrEqualTo(12),
      reason: 'search triggers on notebooks, folders, elements and pages',
    );
  });

  for (var v = 0; v < AppDatabase.latestVersion; v++) {
    test('a database at schema v$v upgrades to a fresh install\'s schema and keeps its data', () {
      final raw = sqlite3.openInMemory();
      AppDatabase.migrateForTest(raw, v);
      _seedOldDatabase(raw);
      final hadFolders = _columns(raw, 'folders').isNotEmpty;
      final hadElements = _columns(raw, 'elements').isNotEmpty;
      final hadPageDetails = _columns(raw, 'pages').contains('bookmarked');
      final hadPaperColor = _columns(raw, 'notebooks').contains('paper_color');

      final upgraded = AppDatabase.fromConnection(raw);
      final fresh = AppDatabase.inMemory();
      addTearDown(fresh.close);

      // (a) Same schema as a fresh install: tables, columns, indexes,
      // triggers and virtual tables.
      expect(_schemaOf(upgraded), _schemaOf(fresh));

      if (v == 0) {
        upgraded.close();
        return; // No tables existed yet, so nothing could be seeded.
      }

      // (b) Seeded rows are readable via the repositories.
      final services = AppServices.create(upgraded);
      addTearDown(services.dispose);
      final physics = services.notebooks.get('nb')!;
      expect(physics.title, 'Physics');
      expect(physics.kind, NotebookKind.paged);
      expect(physics.paper, PaperStyle.lined);
      expect(physics.editedAt, hadFolders ? 400 : 500);
      expect(physics.folderId, hadFolders ? 'fd' : isNull);
      expect(physics.favorite, hadFolders);
      expect(
        services.notebooks.get('cv')!.paperColor,
        hadPaperColor ? PaperColor.cream : PaperColor.white,
      );
      expect(services.notebooks.list().map((n) => n.id), unorderedEquals(['nb', 'cv']));

      final page = services.pages.pagesOf('nb').single;
      expect(page.id, 'pg');
      expect(page.paper, PaperStyle.lined);
      expect(page.bookmarked, hadPageDetails);
      expect(page.paperColor, hadPageDetails ? PaperColor.grey : PaperColor.white);
      expect(page.background, isNull);

      final copier = SurfaceCopier(services.strokes, elements: services.elements);
      for (final (id, surface) in [('s1', 'pg'), ('s2', 'cv')]) {
        final stroke = copier.loadAll(surface).single;
        expect(stroke.id, id);
        expect(stroke.tool, InkTool.pen);
        expect(stroke.style, StrokeStyle.defaultsFor(InkTool.pen));
        expect(stroke.points.last, const StrokePoint(60, 40, 0.5));
      }
      if (hadFolders) expect(services.folders.get('fd')!.name, 'Lectures');
      if (hadElements) {
        expect(copier.loadAllElements('pg').single.data['text'], 'Quantum notes');
      }

      // (c) The search index was filled by the migration.
      final docs = {
        for (final r in upgraded.db.select('SELECT kind, ref_id, body FROM search_docs'))
          '${r['kind']}:${r['ref_id']}': r['body'],
      };
      expect(docs, containsPair('notebook:nb', 'Physics'));
      expect(docs, containsPair('notebook:cv', 'Ideas'));
      if (hadFolders) expect(docs, containsPair('folder:fd', 'Lectures'));
      if (hadElements) expect(docs, containsPair('text:el', 'Quantum notes'));
      final hits = services.search.index.search(SearchQuery('phys'));
      expect(hits.map((h) => (h.kind, h.refId)), contains((SearchHitKind.notebookTitle, 'nb')));
      if (SearchSchema.hasFts(upgraded.db)) {
        final fts = upgraded.db.select(
          "SELECT rowid FROM search_fts WHERE search_fts MATCH 'ideas'",
        );
        expect(fts, hasLength(1), reason: 'search_fts was rebuilt from search_docs');
      }

      // Later writes keep the index current through the triggers.
      services.notebooks.update(physics.copyWith(title: 'Mechanics'));
      expect(services.search.index.search(SearchQuery('phys')), isEmpty);
      expect(services.search.index.search(SearchQuery('mecha')), isNotEmpty);
    });
  }

  test('opening a latest database twice is a no-op', () {
    final path = p.join(dir.path, 'latest.db');
    final first = AppServices.create(AppDatabase.open(path));
    final folder = first.folders.create(name: 'Work', color: 1);
    final nb = first.notebooks.create(
      title: 'Plans',
      kind: NotebookKind.paged,
      paper: PaperStyle.grid,
      coverColor: 1,
      folderId: folder.id,
    );
    final page = first.pages.pagesOf(nb.id).single;
    first.strokes.save([
      Stroke(
        id: 'k',
        surfaceId: page.id,
        tool: InkTool.ballpoint,
        color: 0,
        width: 2,
        points: const [StrokePoint(1, 1, 0.5), StrokePoint(5, 5, 0.5)],
        createdAt: 1,
      ),
    ]);
    final schema = _schemaOf(first.database);
    final contents = _contentsOf(first.database.db);
    first.dispose();

    final again = AppDatabase.open(path);
    expect(
      again.db.select('SELECT total_changes() AS n').first['n'],
      0,
      reason: 'no migration ran',
    );
    expect(_schemaOf(again), schema);
    expect(_contentsOf(again.db), contents);
    again.close();

    // And once more through the whole service graph.
    final third = AppServices.create(AppDatabase.open(path));
    addTearDown(third.dispose);
    expect(_contentsOf(third.database.db), contents);
    expect(third.notebooks.get(nb.id)!.folderId, folder.id);
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
