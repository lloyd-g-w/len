import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sqlite3/common.dart';

import '../platform/sqlite_connection.dart';

import 'search/ink_text_schema.dart';
import 'search/search_schema.dart';

/// Owns the SQLite connection and creates (later: migrates) the schema.
///
/// Every syncable table carries the same bookkeeping columns:
///   * `updated_at` / `device_id` — last-write-wins version (see
///     docs/SYNC_PROTOCOL.md),
///   * `deleted` — tombstone flag, so deletions can be synced,
///   * `dirty` — 1 when the row has local changes not yet pushed.
class AppDatabase {
  AppDatabase._(this.db, {this.path});

  /// Wraps an open connection to the file at [path] (null: in memory or
  /// in a browser), configuring it and applying migrations.
  factory AppDatabase.fromConnection(CommonDatabase db, {String? path}) =>
      AppDatabase._(db, path: path)
        .._configure()
        .._migrate();

  /// Opens (creating if needed) the database file at [path]. Native only.
  factory AppDatabase.open(String path) =>
      AppDatabase.fromConnection(openSqliteFile(path), path: path);

  /// Opens the app's own database `len.db` in [directory] — on the web it
  /// lives in IndexedDB instead and [directory] is ignored.
  static Future<AppDatabase> openDefault(String directory) async => AppDatabase.fromConnection(
    await openSqlite(name: _defaultName, directory: directory),
    path: sqliteFilePath(name: _defaultName, directory: directory),
  );

  static const _defaultName = 'len.db';

  /// An in-memory database, for tests.
  factory AppDatabase.inMemory() => AppDatabase.fromConnection(openSqliteInMemory());

  final CommonDatabase db;

  /// The database file, or null for an in-memory (or browser) database.
  final String? path;

  /// Runs [action] inside a transaction, rolling back if it throws.
  ///
  /// Reentrant: when already inside a transaction, [action] simply joins it
  /// (an exception still propagates to, and rolls back, the outermost one).
  T transaction<T>(T Function() action) {
    if (!db.autocommit) return action();
    db.execute('BEGIN');
    try {
      final result = action();
      db.execute('COMMIT');
      return result;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Whether [close] was called.
  bool get isClosed => _closed;
  bool _closed = false;

  void close() {
    _closed = true;
    db.close();
  }

  void _configure() {
    if (sqliteSupportsWal) db.execute('PRAGMA journal_mode = WAL');
    db.execute('PRAGMA foreign_keys = OFF');
    db.execute('PRAGMA synchronous = NORMAL');
  }

  void _migrate() {
    var version = db.select('PRAGMA user_version').first.columnAt(0) as int;
    if (version > _migrations.length) {
      _resetUnknownSchema(version);
      version = 0;
    }
    for (var v = version; v < _migrations.length; v++) {
      transaction(() {
        _migrations[v](db);
        db.execute('PRAGMA user_version = ${v + 1}');
      });
    }
  }

  /// A database from a newer build or from before the pre-release schema
  /// squash has a schema this build cannot interpret. Pre-release, there is
  /// no upgrade path (see CONVENTIONS.md): the old file is copied aside
  /// (`<path>.schema-<version>-<time>.bak`, native only) and the database is
  /// reset to empty, instead of crashing on missing columns later.
  void _resetUnknownSchema(int version) {
    final file = path;
    if (file != null) {
      final backup = '$file.schema-$version-${DateTime.now().millisecondsSinceEpoch}.bak';
      db.execute("VACUUM INTO '${backup.replaceAll("'", "''")}'");
    }
    final objects = db.select(
      "SELECT type, name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' "
      "AND type IN ('table', 'view') ORDER BY type DESC",
    );
    db.execute('PRAGMA foreign_keys = OFF');
    for (final o in objects) {
      final name = (o['name'] as String).replaceAll('"', '""');
      // Dropping a table drops its indexes and triggers; FTS shadow tables
      // go with their virtual table (IF EXISTS covers both orders).
      db.execute('DROP ${o['type'] == 'view' ? 'VIEW' : 'TABLE'} IF EXISTS "$name"');
    }
    db.execute('PRAGMA user_version = 0');
  }

  /// The schema version of a fully migrated database.
  @visibleForTesting
  static int get latestVersion => _migrations.length;

  /// Ordered list of schema migrations; index i migrates from version i to
  /// i + 1 (`PRAGMA user_version`). Version 1 creates the whole schema.
  /// Future schema changes **append** a migration; never edit one that has
  /// shipped.
  static final List<void Function(CommonDatabase)> _migrations = [
    _createSchema,
    _templates,
    _recordingWaveforms,
    _tags,
  ];

  /// Version 4: tags and which notebooks and pages carry them.
  static void _tags(CommonDatabase db) {
    db.execute('''
      CREATE TABLE tags (
        id          TEXT PRIMARY KEY NOT NULL,
        name        TEXT NOT NULL,
        color       INTEGER NOT NULL,
        created_at  INTEGER NOT NULL,
        updated_at  INTEGER NOT NULL,
        device_id   TEXT NOT NULL,
        deleted     INTEGER NOT NULL DEFAULT 0,
        dirty       INTEGER NOT NULL DEFAULT 1
      )''');
    // `kind`: `notebook` or `page`; the id is derived from tag and target.
    db.execute('''
      CREATE TABLE taggings (
        id          TEXT PRIMARY KEY NOT NULL,
        tag_id      TEXT NOT NULL,
        target_id   TEXT NOT NULL,
        kind        TEXT NOT NULL,
        updated_at  INTEGER NOT NULL,
        device_id   TEXT NOT NULL,
        deleted     INTEGER NOT NULL DEFAULT 0,
        dirty       INTEGER NOT NULL DEFAULT 1
      )''');
    db.execute('CREATE INDEX taggings_by_target ON taggings(target_id)');
    db.execute('CREATE INDEX taggings_by_tag ON taggings(tag_id)');
  }

  /// Version 3: a recording's waveform blob (`''` = none), and stroke
  /// times indexed per surface (ink density of a recording, see
  /// `RecordingRepository.contentTimes`).
  static void _recordingWaveforms(CommonDatabase db) {
    db.execute("ALTER TABLE recordings ADD COLUMN waveform TEXT NOT NULL DEFAULT ''");
    db.execute('DROP INDEX strokes_by_surface');
    db.execute('CREATE INDEX strokes_by_surface ON strokes(surface_id, created_at)');
  }

  /// Version 2: template parameters on pages (`paper_data`, JSON, see
  /// `Paper.toData`), the user's own templates, and folder icons.
  static void _templates(CommonDatabase db) {
    db.execute("ALTER TABLE pages ADD COLUMN paper_data TEXT NOT NULL DEFAULT '{}'");
    db.execute('ALTER TABLE folders ADD COLUMN icon TEXT');
    // A user's template: an image blob and the page size it suggests.
    db.execute('''
      CREATE TABLE templates (
        id          TEXT PRIMARY KEY NOT NULL,
        name        TEXT NOT NULL,
        blob        TEXT NOT NULL,
        width       REAL NOT NULL,
        height      REAL NOT NULL,
        created_at  INTEGER NOT NULL,
        updated_at  INTEGER NOT NULL,
        device_id   TEXT NOT NULL,
        deleted     INTEGER NOT NULL DEFAULT 0,
        dirty       INTEGER NOT NULL DEFAULT 1
      )''');
  }

  /// Creates the complete schema of a new database.
  static void _createSchema(CommonDatabase db) {
    db.execute('''
      CREATE TABLE settings (
        key   TEXT PRIMARY KEY NOT NULL,
        value TEXT NOT NULL
      )''');

    db.execute('''
      CREATE TABLE folders (
        id          TEXT PRIMARY KEY NOT NULL,
        name        TEXT NOT NULL,
        parent_id   TEXT,
        color       INTEGER NOT NULL,
        created_at  INTEGER NOT NULL,
        updated_at  INTEGER NOT NULL,
        device_id   TEXT NOT NULL,
        deleted     INTEGER NOT NULL DEFAULT 0,
        dirty       INTEGER NOT NULL DEFAULT 1
      )''');
    db.execute('CREATE INDEX folders_by_parent ON folders(parent_id)');

    db.execute('''
      CREATE TABLE notebooks (
        id          TEXT PRIMARY KEY NOT NULL,
        title       TEXT NOT NULL,
        kind        TEXT NOT NULL,
        paper       TEXT NOT NULL,
        paper_color TEXT NOT NULL DEFAULT 'white',
        cover_color INTEGER NOT NULL,
        cover_style TEXT NOT NULL DEFAULT 'plain',
        folder_id   TEXT,
        favorite    INTEGER NOT NULL DEFAULT 0,
        trashed_at  INTEGER,
        created_at  INTEGER NOT NULL,
        edited_at   INTEGER NOT NULL DEFAULT 0,
        updated_at  INTEGER NOT NULL,
        device_id   TEXT NOT NULL,
        deleted     INTEGER NOT NULL DEFAULT 0,
        dirty       INTEGER NOT NULL DEFAULT 1
      )''');
    db.execute('CREATE INDEX notebooks_by_folder ON notebooks(folder_id)');

    // `background`: JSON object (see `PageBackground`) or NULL.
    db.execute('''
      CREATE TABLE pages (
        id          TEXT PRIMARY KEY NOT NULL,
        notebook_id TEXT NOT NULL,
        sort_key    REAL NOT NULL,
        width       REAL NOT NULL,
        height      REAL NOT NULL,
        paper       TEXT NOT NULL,
        paper_color TEXT NOT NULL DEFAULT 'white',
        bookmarked  INTEGER NOT NULL DEFAULT 0,
        background  TEXT,
        updated_at  INTEGER NOT NULL,
        device_id   TEXT NOT NULL,
        deleted     INTEGER NOT NULL DEFAULT 0,
        dirty       INTEGER NOT NULL DEFAULT 1
      )''');
    db.execute('CREATE INDEX pages_by_notebook ON pages(notebook_id, sort_key)');

    // `style`: JSON (see `StrokeStyle`).
    db.execute('''
      CREATE TABLE strokes (
        id          TEXT PRIMARY KEY NOT NULL,
        surface_id  TEXT NOT NULL,
        tool        TEXT NOT NULL,
        color       INTEGER NOT NULL,
        width       REAL NOT NULL,
        style       TEXT,
        points      BLOB NOT NULL,
        created_at  INTEGER NOT NULL,
        updated_at  INTEGER NOT NULL,
        device_id   TEXT NOT NULL,
        deleted     INTEGER NOT NULL DEFAULT 0,
        dirty       INTEGER NOT NULL DEFAULT 1
      )''');
    db.execute('CREATE INDEX strokes_by_surface ON strokes(surface_id)');

    // Sparse spatial index: which chunks of a surface each live stroke
    // touches. Only populated chunks have rows, so an infinite canvas costs
    // nothing where it is empty. Derived data — never synced.
    db.execute('''
      CREATE TABLE stroke_chunks (
        surface_id TEXT NOT NULL,
        cx         INTEGER NOT NULL,
        cy         INTEGER NOT NULL,
        stroke_id  TEXT NOT NULL,
        PRIMARY KEY (surface_id, cx, cy, stroke_id)
      ) WITHOUT ROWID''');
    db.execute('CREATE INDEX stroke_chunks_by_stroke ON stroke_chunks(stroke_id)');

    // Non-ink objects on a surface (text boxes, images) and their sparse
    // chunk index, mirroring `strokes` / `stroke_chunks`.
    db.execute('''
      CREATE TABLE elements (
        id          TEXT PRIMARY KEY NOT NULL,
        surface_id  TEXT NOT NULL,
        type        TEXT NOT NULL,
        x           REAL NOT NULL,
        y           REAL NOT NULL,
        w           REAL NOT NULL,
        h           REAL NOT NULL,
        rotation    REAL NOT NULL DEFAULT 0,
        z           REAL NOT NULL DEFAULT 0,
        data        TEXT NOT NULL,
        created_at  INTEGER NOT NULL,
        updated_at  INTEGER NOT NULL,
        device_id   TEXT NOT NULL,
        deleted     INTEGER NOT NULL DEFAULT 0,
        dirty       INTEGER NOT NULL DEFAULT 1
      )''');
    db.execute('CREATE INDEX elements_by_surface ON elements(surface_id)');
    db.execute('''
      CREATE TABLE element_chunks (
        surface_id TEXT NOT NULL,
        cx         INTEGER NOT NULL,
        cy         INTEGER NOT NULL,
        element_id TEXT NOT NULL,
        PRIMARY KEY (surface_id, cx, cy, element_id)
      ) WITHOUT ROWID''');
    db.execute('CREATE INDEX element_chunks_by_element ON element_chunks(element_id)');

    // Audio recordings of notebooks (the audio itself is a blob).
    db.execute('''
      CREATE TABLE recordings (
        id          TEXT PRIMARY KEY NOT NULL,
        notebook_id TEXT NOT NULL,
        blob        TEXT NOT NULL,
        duration_ms INTEGER NOT NULL,
        started_at  INTEGER NOT NULL,
        title       TEXT NOT NULL,
        mime        TEXT NOT NULL,
        segments    TEXT NOT NULL DEFAULT '[]',
        updated_at  INTEGER NOT NULL,
        device_id   TEXT NOT NULL,
        deleted     INTEGER NOT NULL DEFAULT 0,
        dirty       INTEGER NOT NULL DEFAULT 1
      )''');
    db.execute('CREATE INDEX recordings_by_notebook ON recordings(notebook_id, started_at)');

    // Sync pushes dirty rows in id order (keyset pagination); index exactly
    // that for the big tables, so a sync with nothing to push scans nothing.
    for (final table in ['strokes', 'elements', 'recordings']) {
      db.execute('CREATE INDEX ${table}_dirty ON $table(id) WHERE dirty = 1');
    }

    // Blob files live in the app support directory; this table records
    // which ones are present and their sync / garbage collection state:
    // `uploaded` to the current server, `rejected_limit` when the server
    // refused the blob as too large (its limit at the time, 0 if unknown),
    // `unreferenced_since` (ms) when no live row was last found
    // referencing it.
    db.execute('''
      CREATE TABLE blobs (
        sha256             TEXT PRIMARY KEY NOT NULL,
        size               INTEGER NOT NULL,
        mime               TEXT NOT NULL,
        created_at         INTEGER NOT NULL,
        uploaded           INTEGER NOT NULL DEFAULT 0,
        rejected_limit     INTEGER,
        unreferenced_since INTEGER
      )''');

    // Derived and local only (never synced): the full-text search index and
    // recognised handwriting.
    SearchSchema.create(db);
    InkTextSchema.create(db);
  }
}
