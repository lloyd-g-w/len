import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:sqlite3/common.dart';

import '../platform/sqlite_connection.dart';

import 'schema_reset.dart';
import 'search/ink_text_schema.dart';
import 'search/search_schema.dart';
import 'write_back.dart';

/// Owns the SQLite connection and creates and migrates the schema.
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
  /// lives in IndexedDB instead, [directory] is ignored and the database
  /// joins [writes] (whose writes reach storage asynchronously).
  static Future<AppDatabase> openDefault(String directory, {StorageWrites? writes}) async {
    _expected ??= _shapeOfFresh(await openSqliteScratch());
    return AppDatabase.fromConnection(
      await openSqlite(name: _defaultName, directory: directory, writes: writes),
      path: sqliteFilePath(name: _defaultName, directory: directory),
    );
  }

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
    final version = _version;
    var kept = const <String, String>{};
    if (version > _migrations.length || (version == 0 && !SchemaCheck.isEmpty(db))) {
      kept = _reset(version);
    } else if (version > 0) {
      try {
        _upgrade(version);
      } on SqliteException catch (e) {
        debugPrint('Migrating the database from version $version failed: $e');
        kept = _reset(version);
      }
      if (schemaReset == null && !SchemaCheck.shapeOf(db).containsAll(_expectedShape())) {
        kept = _reset(version);
      }
    }
    _upgrade(_version);
    for (final MapEntry(:key, :value) in kept.entries) {
      db.execute('INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)', [key, value]);
    }
  }

  int get _version => db.select('PRAGMA user_version').first.columnAt(0) as int;

  void _upgrade(int from) {
    for (var v = from; v < _migrations.length; v++) {
      transaction(() {
        _migrations[v](db);
        db.execute('PRAGMA user_version = ${v + 1}');
      });
    }
  }

  /// Set when this database was found with a schema this build can't use
  /// and was started afresh, until [acknowledgeSchemaReset] (the library
  /// tells the user once).
  SchemaReset? get schemaReset => _schemaReset;
  SchemaReset? _schemaReset;

  void acknowledgeSchemaReset() => _schemaReset = null;

  /// A database from a newer build, or one whose schema differs from what
  /// the migrations produce (they were rewritten pre-release), can't be
  /// used. Pre-release there is no upgrade path (see CONVENTIONS.md): the
  /// old file is kept aside (native only) and the database starts empty,
  /// instead of failing on missing tables or columns later.
  /// Returns the settings to write back ([SchemaCheck.keptSettings]).
  Map<String, String> _reset(int version) {
    final (backup, kept) = SchemaCheck.reset(db, path: path, version: version);
    _schemaReset = SchemaReset(
      backupPath: backup,
      keptSync: kept.length == SchemaCheck.keptSettings.length,
      fromNewer: version > _migrations.length,
    );
    debugPrint('Database schema (version $version) not usable; started fresh (backup: $backup)');
    return kept;
  }

  /// The shape of a freshly migrated database ([SchemaCheck.shapeOf]),
  /// computed once per run on a scratch in-memory database. [openDefault]
  /// prepares it asynchronously (browsers can't open one synchronously).
  static Set<String> _expectedShape() => _expected ??= _shapeOfFresh(openSqliteInMemory());
  static Set<String>? _expected;

  static Set<String> _shapeOfFresh(CommonDatabase scratch) {
    final fresh = AppDatabase.fromConnection(scratch);
    try {
      return SchemaCheck.shapeOf(fresh.db);
    } finally {
      fresh.close();
    }
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
    _organise,
    _recordingParts,
    _recordingTrim,
    _notebookPaperData,
    _strokeEndStyles,
    _recognisedText,
  ];

  /// Version 9: recognised handwriting, synced (collection
  /// `recognised_text`, see `RecognisedTextRepository`); remote records
  /// queue their surface for indexing.
  static void _recognisedText(CommonDatabase db) {
    db.execute('''
      CREATE TABLE recognised_text (
        id          TEXT PRIMARY KEY NOT NULL,
        language    TEXT NOT NULL,
        lines       TEXT NOT NULL,
        updated_at  INTEGER NOT NULL,
        device_id   TEXT NOT NULL,
        deleted     INTEGER NOT NULL DEFAULT 0,
        dirty       INTEGER NOT NULL DEFAULT 1
      )''');
    InkTextSchema.createSyncedTriggers(db);
  }

  /// Version 8: make the pen's end shape explicit on stored strokes. Upgrade
  /// the on-disk JSON once rather than keeping a legacy read path in the
  /// renderer; bump the record version so already-synced strokes are sent
  /// again with the now-complete style.
  static void _strokeEndStyles(CommonDatabase db) {
    db.execute('''
      UPDATE strokes
      SET style = json_set(style, '\$.e', 'round'),
          updated_at = updated_at + 1,
          dirty = 1
      WHERE style IS NOT NULL AND json_valid(style) AND json_type(style) = 'object'
        AND json_extract(style, '\$.e') IS NULL
    ''');
  }

  /// Version 7: a notebook's paper look (`paper_data`, JSON, `Paper.toData`
  /// of its default paper: the canvas background and new pages).
  static void _notebookPaperData(CommonDatabase db) {
    db.execute("ALTER TABLE notebooks ADD COLUMN paper_data TEXT NOT NULL DEFAULT '{}'");
  }

  /// Version 6: a recording's kept range (`trim_start_ms`, `trim_end_ms`;
  /// untrimmed = `0` and `duration_ms`).
  static void _recordingTrim(CommonDatabase db) {
    db.execute('ALTER TABLE recordings ADD COLUMN trim_start_ms INTEGER NOT NULL DEFAULT 0');
    db.execute('ALTER TABLE recordings ADD COLUMN trim_end_ms INTEGER NOT NULL DEFAULT 0');
    db.execute('UPDATE recordings SET trim_end_ms = duration_ms');
  }

  /// Version 5: a recording's audio is a list of parts (`audio`, JSON
  /// `[[blob, durationMs], …]`) instead of one `blob`.
  static void _recordingParts(CommonDatabase db) {
    db.execute("ALTER TABLE recordings ADD COLUMN audio TEXT NOT NULL DEFAULT '[]'");
    db.execute('UPDATE recordings SET audio = json_array(json_array(blob, duration_ms))');
    db.execute('ALTER TABLE recordings DROP COLUMN blob');
  }

  /// Version 4: notebooks' own outlines.
  static void _organise(CommonDatabase db) {
    // A notebook's own table of contents; siblings follow page order.
    db.execute('''
      CREATE TABLE outline (
        id          TEXT PRIMARY KEY NOT NULL,
        notebook_id TEXT NOT NULL,
        page_id     TEXT NOT NULL,
        parent_id   TEXT,
        title       TEXT NOT NULL,
        created_at  INTEGER NOT NULL,
        updated_at  INTEGER NOT NULL,
        device_id   TEXT NOT NULL,
        deleted     INTEGER NOT NULL DEFAULT 0,
        dirty       INTEGER NOT NULL DEFAULT 1
      )''');
    db.execute('CREATE INDEX outline_by_notebook ON outline(notebook_id)');
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
  /// `Paper.toData`), and the user's own templates.
  static void _templates(CommonDatabase db) {
    db.execute("ALTER TABLE pages ADD COLUMN paper_data TEXT NOT NULL DEFAULT '{}'");
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
