import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/search/search_index.dart';
import 'package:len/data/search/search_query.dart';
import 'package:len/data/search/search_schema.dart';
import 'package:len/domain/chunk_digest.dart';
import 'package:len/domain/chunk_grid.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/recording.dart';
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

  test('a new database gets the whole schema at the latest user_version', () {
    final fresh = AppDatabase.inMemory();
    addTearDown(fresh.close);
    final schema = _schemaOf(fresh);
    expect(schema['version'], 15);
    expect(AppDatabase.latestVersion, 15);
    // Version 7: a notebook's paper look.
    expect(schema['notebooks'], contains("paper_data TEXT 1 '{}' 0"));
    // Version 3: recording waveforms, stroke times per surface.
    expect(schema['recordings'], contains("waveform TEXT 1 '' 0"));
    // Version 5: recordings in parts.
    expect(schema['recordings'], contains("audio TEXT 1 '[]' 0"));
    expect(schema['recordings'], isNot(contains('blob ')));
    // Version 6: trimmed recordings.
    expect(schema['recordings'], contains('trim_start_ms INTEGER 1 0 0'));
    expect(schema['recordings'], contains('trim_end_ms INTEGER 1 0 0'));
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
        'templates',
        'outline',
        'blobs',
        'search_docs',
        'pdf_text',
        'pdf_text_blobs',
        'ink_text',
        'ink_text_queue',
        'recognised_text',
        'notebook_styles',
        'freed_blobs',
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
    expect(
      [for (final c in fresh.db.select('PRAGMA index_info(strokes_by_surface)')) c['name']],
      ['surface_id', 'created_at'],
    );
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

  test('version 5 turns a recording\'s blob into its one part', () {
    final path = p.join(dir.path, 'len.db');
    final db = AppDatabase.open(path);
    // Back to version 4's recordings table.
    db.db.execute("ALTER TABLE recordings ADD COLUMN blob TEXT NOT NULL DEFAULT ''");
    db.db.execute('ALTER TABLE recordings DROP COLUMN audio');
    db.db.execute('ALTER TABLE recordings DROP COLUMN trim_start_ms');
    db.db.execute('ALTER TABLE recordings DROP COLUMN trim_end_ms');
    db.db.execute('ALTER TABLE notebooks DROP COLUMN paper_data');
    db.db.execute('DROP TABLE recognised_text');
    _dropChunkDigests(db.db);
    db.db.execute('''
      INSERT INTO recordings (id, notebook_id, blob, duration_ms, started_at, title, mime,
                              updated_at, device_id)
      VALUES ('r', 'n', '${'ab' * 32}', 1234, 5, 'Talk', 'audio/mp4', 1, 'd')''');
    db.db.execute('PRAGMA user_version = 4');
    db.close();
    final s = AppServices.create(AppDatabase.open(path));
    addTearDown(s.dispose);
    expect(s.recordings.get('r')!.parts, [RecordingPart('ab' * 32, 1234)]);
    // Version 6 keeps all of it.
    final r = s.recordings.get('r')!;
    expect((r.trimStartMs, r.trimEndMs, r.trimmed), (0, 1234, false));
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

  test('upgrading stored pen strokes keeps their ink and syncs the end style', () {
    final path = p.join(dir.path, 'len.db');
    final old = AppDatabase.open(path);
    final services = AppServices.create(old);
    final notebook = services.notebooks.create(
      title: 'Old ink',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 1,
    );
    final page = services.pages.pagesOf(notebook.id).single;
    services.strokes.save([
      Stroke(
        id: 'before-ends',
        surfaceId: page.id,
        tool: InkTool.ballpoint,
        color: 0xFF000000,
        width: 2,
        points: const [StrokePoint(1, 1, 0.5), StrokePoint(10, 1, 0.5)],
        createdAt: 1,
      ),
    ]);
    old.db.execute(
      "UPDATE strokes SET style = '{\"o\":1,\"th\":0.5,\"sl\":0}', "
      "updated_at = 100, dirty = 0 WHERE id = 'before-ends'",
    );
    old.db.execute('DROP TABLE recognised_text');
    _dropChunkDigests(old.db);
    old.db.execute('PRAGMA user_version = 7');
    services.dispose();

    final upgraded = AppDatabase.open(path);
    final row = upgraded.db.select("SELECT * FROM strokes WHERE id = 'before-ends'").single;
    expect(row['updated_at'], 101);
    expect(row['dirty'], 1);
    expect(row['style'], contains('"e":"round"'));
    final restored = AppServices.create(upgraded);
    addTearDown(restored.dispose);
    expect(
      restored.strokes.loadChunks(page.id, [(x: 0, y: 0)]).single.style.ends,
      StrokeEnds.round,
    );
    expect(restored.strokes.dirtyRecords(10).single.id, 'before-ends');
  });

  test('version 10 rebuilds the chunk indexes with digests', () {
    final path = p.join(dir.path, 'len.db');
    final services = AppServices.create(AppDatabase.open(path));
    final stroke = Stroke(
      id: 'long',
      surfaceId: 's',
      tool: InkTool.ballpoint,
      color: 0,
      width: 2,
      points: const [StrokePoint(10, 10, 0.5), StrokePoint(1000, 10, 0.5)],
      createdAt: 1,
    );
    services.strokes.save([stroke]);
    final db = services.database.db;
    _dropChunkDigests(db);
    // An index row from before, over the whole bounding box.
    db.execute("INSERT INTO stroke_chunks VALUES ('s', 1, 1, 'long')");
    db.execute('PRAGMA user_version = 9');
    services.dispose();

    final upgraded = AppServices.create(AppDatabase.open(path));
    addTearDown(upgraded.dispose);
    final digests = upgraded.strokes.chunkDigests('s', const ChunkRange(-4, -4, 4, 4));
    expect(digests.keys.toSet(), {(x: 0, y: 0), (x: 1, y: 0)});
    expect(digests[(x: 0, y: 0)], ChunkDigest.of([stroke], const []));
  });

  test('a database with an unknown (pre-squash or newer) schema is backed up and reset', () {
    final dir = Directory.systemTemp.createTempSync('len_schema_reset');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/len.db';
    // A pre-squash development database: user_version 12, an old table.
    AppDatabase.open(path).close();
    final raw = AppDatabase.open(path);
    raw.db
      ..execute('CREATE TABLE legacy_only (x INTEGER)')
      ..execute('DROP TABLE IF EXISTS blobs')
      ..execute('DROP TABLE freed_blobs')
      ..execute('PRAGMA user_version = 12');
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

    final backups = dir.listSync().where((f) => f.path.contains('.schema-12-')).toList();
    expect(backups, hasLength(1), reason: 'the old file is kept aside');
  });
}

/// Back to before version 10 (the chunk indexes): undoes versions 10 to 15
/// of a fresh database (14 only rewrites data).
void _dropChunkDigests(CommonDatabase db) {
  for (final table in ['elements', 'recordings', 'outline']) {
    db.execute('DROP TRIGGER ${table}_deleted');
    db.execute('DROP TRIGGER ${table}_tombstone_versions');
    for (final column in ['base_at', 'base_device', 'origin_at', 'origin_device', 'origin_for']) {
      db.execute('ALTER TABLE $table DROP COLUMN $column');
    }
  }
  db.execute('ALTER TABLE stroke_chunks DROP COLUMN digest');
  db.execute('ALTER TABLE element_chunks DROP COLUMN digest');
  db.execute('DROP INDEX strokes_tombstone_payloads');
  db.execute('DROP INDEX elements_tombstone_payloads');
  db.execute('DROP TABLE notebook_styles');
  db.execute('DROP TABLE freed_blobs');
}
