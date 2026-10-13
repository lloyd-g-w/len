import 'package:sqlite3/common.dart';

import 'search/ink_text_schema.dart';
import 'search/search_schema.dart';

/// Schema version 1: every table of a new database.
///
/// Every syncable table carries the same bookkeeping columns:
///   * `updated_at` / `device_id` — last-write-wins version (see
///     docs/SYNC_PROTOCOL.md),
///   * `deleted` — tombstone flag, so deletions can be synced,
///   * `dirty` — 1 when the row has local changes not yet pushed.
abstract final class InitialSchema {
  /// Creates the complete schema of a new database.
  static void create(CommonDatabase db) {
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
