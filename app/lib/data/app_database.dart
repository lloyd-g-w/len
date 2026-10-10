import 'package:sqlite3/common.dart';

import '../platform/sqlite_connection.dart';

/// Owns the SQLite connection and applies schema migrations.
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

  void close() => db.close();

  void _configure() {
    if (sqliteSupportsWal) db.execute('PRAGMA journal_mode = WAL');
    db.execute('PRAGMA foreign_keys = OFF');
    db.execute('PRAGMA synchronous = NORMAL');
  }

  void _migrate() {
    final version = db.select('PRAGMA user_version').first.columnAt(0) as int;
    for (var v = version; v < _migrations.length; v++) {
      transaction(() {
        _migrations[v](db);
        db.execute('PRAGMA user_version = ${v + 1}');
      });
    }
  }

  /// Schema version from which the page/blob migration runs (its index in
  /// [_migrations]); lets tests rewind a database without hard-coding it.
  static int get versionBeforePageDetailsAndBlobs => _migrations.indexOf(_addPageDetailsAndBlobs);

  /// Ordered list of schema migrations; index i migrates from version i.
  /// Never edit an existing entry — append a new one instead.
  static final List<void Function(CommonDatabase)> _migrations = [
    _createInitialSchema,
    _indexDirtyStrokesById,
    _addStrokeStyle,
    _addFoldersAndLibraryFields,
    _addPageDetailsAndBlobs,
    _createElements,
    _addNotebookPaperColor,
  ];

  /// Surface elements (text boxes; later images) and their sparse chunk
  /// index, mirroring `strokes` / `stroke_chunks`. Idempotent, so it is safe
  /// however migrations from parallel branches end up ordered.
  static void _createElements(CommonDatabase db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS elements (
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
    db.execute('CREATE INDEX IF NOT EXISTS elements_by_surface ON elements(surface_id)');
    db.execute('CREATE INDEX IF NOT EXISTS elements_dirty ON elements(id) WHERE dirty = 1');
    db.execute('''
      CREATE TABLE IF NOT EXISTS element_chunks (
        surface_id TEXT NOT NULL,
        cx         INTEGER NOT NULL,
        cy         INTEGER NOT NULL,
        element_id TEXT NOT NULL,
        PRIMARY KEY (surface_id, cx, cy, element_id)
      ) WITHOUT ROWID''');
    db.execute(
      'CREATE INDEX IF NOT EXISTS element_chunks_by_element ON element_chunks(element_id)',
    );
  }

  /// Background colour of infinite canvases. Idempotent (parallel branches
  /// may order migrations differently).
  static void _addNotebookPaperColor(CommonDatabase db) {
    final columns = db.select('PRAGMA table_info(notebooks)').map((r) => r['name']).toSet();
    if (!columns.contains('paper_color')) {
      db.execute("ALTER TABLE notebooks ADD COLUMN paper_color TEXT NOT NULL DEFAULT 'white'");
    }
  }

  /// Per-stroke rendering style (JSON, see `StrokeStyle`); NULL for strokes
  /// drawn before styles existed. Idempotent, so it is safe however
  /// migrations from parallel branches end up ordered.
  static void _addStrokeStyle(CommonDatabase db) {
    final columns = db.select('PRAGMA table_info(strokes)').map((r) => r['name']);
    if (!columns.contains('style')) db.execute('ALTER TABLE strokes ADD COLUMN style TEXT');
  }

  /// Library organisation: nested folders, plus per-notebook folder,
  /// favourite, trash, cover pattern and last-edit time.
  static void _addFoldersAndLibraryFields(CommonDatabase db) {
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
    db.execute('ALTER TABLE notebooks ADD COLUMN folder_id TEXT');
    db.execute('ALTER TABLE notebooks ADD COLUMN favorite INTEGER NOT NULL DEFAULT 0');
    db.execute('ALTER TABLE notebooks ADD COLUMN trashed_at INTEGER');
    db.execute("ALTER TABLE notebooks ADD COLUMN cover_style TEXT NOT NULL DEFAULT 'plain'");
    db.execute('ALTER TABLE notebooks ADD COLUMN edited_at INTEGER NOT NULL DEFAULT 0');
    db.execute('UPDATE notebooks SET edited_at = updated_at');
    db.execute('CREATE INDEX notebooks_by_folder ON notebooks(folder_id)');
  }

  /// Paper colour, bookmarks and backgrounds (PDF pages) for pages, plus
  /// the local index of content-addressed blob files. Idempotent, like
  /// [_addStrokeStyle]; it also re-applies that one, because databases
  /// created by the pre-merge documents branch recorded this migration at
  /// index 2 and so skip [_addStrokeStyle].
  static void _addPageDetailsAndBlobs(CommonDatabase db) {
    _addStrokeStyle(db);
    final columns = db.select('PRAGMA table_info(pages)').map((r) => r['name']).toSet();
    if (!columns.contains('paper_color')) {
      db.execute("ALTER TABLE pages ADD COLUMN paper_color TEXT NOT NULL DEFAULT 'white'");
    }
    if (!columns.contains('bookmarked')) {
      db.execute('ALTER TABLE pages ADD COLUMN bookmarked INTEGER NOT NULL DEFAULT 0');
    }
    // JSON object (see PageBackground) or NULL.
    if (!columns.contains('background')) {
      db.execute('ALTER TABLE pages ADD COLUMN background TEXT');
    }
    // Blob files live in the app support directory; this table records
    // which ones are present and which still need uploading.
    db.execute('''
      CREATE TABLE IF NOT EXISTS blobs (
        sha256     TEXT PRIMARY KEY NOT NULL,
        size       INTEGER NOT NULL,
        mime       TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        uploaded   INTEGER NOT NULL DEFAULT 0
      )''');
  }

  /// Push pages through dirty rows in id order (keyset pagination); index
  /// exactly that, so a sync with nothing to push never scans all strokes.
  static void _indexDirtyStrokesById(CommonDatabase db) {
    db.execute('DROP INDEX IF EXISTS strokes_dirty');
    db.execute('CREATE INDEX strokes_dirty ON strokes(id) WHERE dirty = 1');
  }

  static void _createInitialSchema(CommonDatabase db) {
    db.execute('''
      CREATE TABLE notebooks (
        id          TEXT PRIMARY KEY NOT NULL,
        title       TEXT NOT NULL,
        kind        TEXT NOT NULL,
        paper       TEXT NOT NULL,
        cover_color INTEGER NOT NULL,
        created_at  INTEGER NOT NULL,
        updated_at  INTEGER NOT NULL,
        device_id   TEXT NOT NULL,
        deleted     INTEGER NOT NULL DEFAULT 0,
        dirty       INTEGER NOT NULL DEFAULT 1
      )''');

    db.execute('''
      CREATE TABLE pages (
        id          TEXT PRIMARY KEY NOT NULL,
        notebook_id TEXT NOT NULL,
        sort_key    REAL NOT NULL,
        width       REAL NOT NULL,
        height      REAL NOT NULL,
        paper       TEXT NOT NULL,
        updated_at  INTEGER NOT NULL,
        device_id   TEXT NOT NULL,
        deleted     INTEGER NOT NULL DEFAULT 0,
        dirty       INTEGER NOT NULL DEFAULT 1
      )''');
    db.execute('CREATE INDEX pages_by_notebook ON pages(notebook_id, sort_key)');

    db.execute('''
      CREATE TABLE strokes (
        id          TEXT PRIMARY KEY NOT NULL,
        surface_id  TEXT NOT NULL,
        tool        TEXT NOT NULL,
        color       INTEGER NOT NULL,
        width       REAL NOT NULL,
        points      BLOB NOT NULL,
        created_at  INTEGER NOT NULL,
        updated_at  INTEGER NOT NULL,
        device_id   TEXT NOT NULL,
        deleted     INTEGER NOT NULL DEFAULT 0,
        dirty       INTEGER NOT NULL DEFAULT 1
      )''');
    db.execute('CREATE INDEX strokes_by_surface ON strokes(surface_id)');
    db.execute('CREATE INDEX strokes_dirty ON strokes(dirty) WHERE dirty = 1');

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

    db.execute('''
      CREATE TABLE settings (
        key   TEXT PRIMARY KEY NOT NULL,
        value TEXT NOT NULL
      )''');
  }
}
