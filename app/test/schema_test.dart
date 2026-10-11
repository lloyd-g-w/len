import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/search/search_index.dart';
import 'package:len/data/search/search_query.dart';
import 'package:len/data/search/search_schema.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/common.dart';

/// [sql] with runs of whitespace collapsed (and none around parentheses
/// and commas), so formatting differences do not matter.
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

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('len_schema_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('a new database gets the whole schema at user_version 1', () {
    final fresh = AppDatabase.inMemory();
    addTearDown(fresh.close);
    final schema = _schemaOf(fresh);
    expect(schema['version'], 1);
    expect(AppDatabase.latestVersion, 1);
    expect(
      schema.keys,
      containsAll([
        'settings',
        'folders',
        'notebooks',
        'pages',
        'strokes',
        'stroke_chunks',
        'elements',
        'element_chunks',
        'recordings',
        'blobs',
        'search_docs',
        'pdf_text',
        'pdf_text_blobs',
        'ink_text',
        'ink_text_queue',
      ]),
    );
    final indexes = (schema['indexes']! as List<String>).join('\n');
    for (final name in [
      'folders_by_parent',
      'notebooks_by_folder',
      'pages_by_notebook',
      'strokes_by_surface',
      'strokes_dirty',
      'stroke_chunks_by_stroke',
      'elements_by_surface',
      'elements_dirty',
      'element_chunks_by_element',
      'recordings_by_notebook',
      'recordings_dirty',
      'search_docs_by_surface',
      'ink_text_by_surface',
      'ink_text_queue_by_version',
    ]) {
      expect(indexes, contains('.$name:'));
    }
    expect(SearchSchema.hasFts(fresh.db), isTrue, reason: 'FTS5 is bundled, so search_fts exists');
    expect(
      (schema['triggers']! as List).length,
      greaterThanOrEqualTo(12),
      reason: 'search triggers on notebooks, folders, elements and pages',
    );
  });

  test('a new database works end to end: search triggers and the ink text queue', () {
    final services = AppServices.create(AppDatabase.inMemory());
    addTearDown(services.dispose);
    final nb = services.notebooks.create(
      title: 'Physics',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 1,
    );
    final page = services.pages.pagesOf(nb.id).single;
    services.strokes.save([
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
    final hits = services.search.index.search(SearchQuery('phys'));
    expect(hits.map((h) => (h.kind, h.refId)), contains((SearchHitKind.notebookTitle, nb.id)));
    final queued = services.database.db.select('SELECT surface_id FROM ink_text_queue');
    expect(queued.map((r) => r['surface_id']), [page.id]);
  });

  test('reopening a database is a no-op', () {
    final path = p.join(dir.path, 'len.db');
    final first = AppServices.create(AppDatabase.open(path));
    final folder = first.folders.create(name: 'Work', color: 1);
    final nb = first.notebooks.create(
      title: 'Plans',
      kind: NotebookKind.paged,
      paper: PaperStyle.gridLarge,
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

  test('a database with an unknown (pre-squash or newer) schema is backed up and reset', () {
    final dir = Directory.systemTemp.createTempSync('len_schema_reset');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/len.db';
    // A pre-squash development database: user_version 11, an old table.
    AppDatabase.open(path).close();
    final raw = AppDatabase.open(path);
    raw.db
      ..execute('CREATE TABLE legacy_only (x INTEGER)')
      ..execute('DROP TABLE IF EXISTS blobs')
      ..execute('PRAGMA user_version = 11');
    raw.close();

    final reopened = AppDatabase.open(path);
    final version = reopened.db.select('PRAGMA user_version').first.columnAt(0);
    expect(version, AppDatabase.latestVersion);
    final tables = reopened.db
        .select("SELECT name FROM sqlite_master WHERE type = 'table'")
        .map((r) => r['name'])
        .toList();
    expect(tables, contains('blobs'));
    expect(tables, isNot(contains('legacy_only')));
    reopened.close();

    final backups = dir.listSync().where((f) => f.path.contains('.schema-11-')).toList();
    expect(backups, hasLength(1), reason: 'the old file is kept aside');
  });
}
