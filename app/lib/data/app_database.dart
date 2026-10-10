import 'package:sqlite3/sqlite3.dart';

/// Owns the SQLite connection and applies schema migrations.
///
/// Every syncable table carries the same bookkeeping columns:
///   * `updated_at` / `device_id` — last-write-wins version (see
///     docs/SYNC_PROTOCOL.md),
///   * `deleted` — tombstone flag, so deletions can be synced,
///   * `dirty` — 1 when the row has local changes not yet pushed.
class AppDatabase {
  AppDatabase._(this.db);

  /// Opens (creating if needed) the database file at [path].
  factory AppDatabase.open(String path) => AppDatabase._(sqlite3.open(path))
    .._configure()
    .._migrate();

  /// An in-memory database, for tests.
  factory AppDatabase.inMemory() => AppDatabase._(sqlite3.openInMemory())
    .._configure()
    .._migrate();

  final Database db;

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
    db.execute('PRAGMA journal_mode = WAL');
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

  /// Ordered list of schema migrations; index i migrates from version i.
  /// Never edit an existing entry — append a new one instead.
  static final List<void Function(Database)> _migrations = [
    _createInitialSchema,
    _indexDirtyStrokesById,
    _addPageDetailsAndBlobs,
  ];

  /// Paper colour, bookmarks and backgrounds (PDF pages) for pages, plus
  /// the local index of content-addressed blob files.
  static void _addPageDetailsAndBlobs(Database db) {
    db.execute("ALTER TABLE pages ADD COLUMN paper_color TEXT NOT NULL DEFAULT 'white'");
    db.execute('ALTER TABLE pages ADD COLUMN bookmarked INTEGER NOT NULL DEFAULT 0');
    // JSON object (see PageBackground) or NULL.
    db.execute('ALTER TABLE pages ADD COLUMN background TEXT');
    // Blob files live in the app support directory; this table records
    // which ones are present and which still need uploading.
    db.execute('''
      CREATE TABLE blobs (
        sha256     TEXT PRIMARY KEY NOT NULL,
        size       INTEGER NOT NULL,
        mime       TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        uploaded   INTEGER NOT NULL DEFAULT 0
      )''');
  }

  /// Push pages through dirty rows in id order (keyset pagination); index
  /// exactly that, so a sync with nothing to push never scans all strokes.
  static void _indexDirtyStrokesById(Database db) {
    db.execute('DROP INDEX IF EXISTS strokes_dirty');
    db.execute('CREATE INDEX strokes_dirty ON strokes(id) WHERE dirty = 1');
  }

  static void _createInitialSchema(Database db) {
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
