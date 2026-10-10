import 'package:sqlite3/common.dart';

import 'search_schema.dart';

/// Recognised handwriting: a local, derived table (never synced).
///
/// * `ink_text` — one row per recognised line on a surface: its text, the
///   line's bounds, per-word boxes (JSON `[[x, y, w, h], …]` matching the
///   text's words, or NULL when they could not be matched), the recognition
///   language, and a key of its strokes, so lines whose strokes did not
///   change are not recognised again.
/// * `ink_text_queue` — surfaces whose strokes changed since they were last
///   recognised, filled by triggers on `strokes` (local edits, undo, sync —
///   whatever wrote them). `version` grows with every change, so a change
///   made while a surface is being recognised re-queues it.
///
/// Triggers mirror `ink_text` into `search_docs` (kind
/// [SearchSchema.handwriting], `ref_id` = the row id).
abstract final class InkTextSchema {
  /// Creates the tables and triggers (idempotent) and queues every surface
  /// with ink.
  static void create(CommonDatabase db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS ink_text (
        id         INTEGER PRIMARY KEY,
        surface_id TEXT NOT NULL,
        stroke_key TEXT NOT NULL,
        language   TEXT NOT NULL,
        text       TEXT NOT NULL,
        x REAL NOT NULL, y REAL NOT NULL, w REAL NOT NULL, h REAL NOT NULL,
        words      TEXT
      )''');
    db.execute('CREATE INDEX IF NOT EXISTS ink_text_by_surface ON ink_text(surface_id)');
    db.execute('''
      CREATE TABLE IF NOT EXISTS ink_text_queue (
        surface_id TEXT PRIMARY KEY NOT NULL,
        version    INTEGER NOT NULL
      )''');
    // Keeps max(version) — computed by every stroke write — a lookup, even
    // where nothing drains the queue (no recogniser on the platform).
    db.execute('CREATE INDEX IF NOT EXISTS ink_text_queue_by_version ON ink_text_queue(version)');
    _createTriggers(db);
    queueAll(db);
  }

  /// Queues every surface with live ink (after a language change, or
  /// when indexing is switched back on).
  static void queueAll(CommonDatabase db) => db.execute('''
      INSERT INTO ink_text_queue (surface_id, version)
      SELECT DISTINCT surface_id, ${_nextVersion()} FROM strokes WHERE deleted = 0
      ON CONFLICT (surface_id) DO UPDATE SET version = excluded.version''');

  static String _nextVersion() => '(SELECT coalesce(max(version), 0) + 1 FROM ink_text_queue)';

  // An upsert, not INSERT OR REPLACE: a trigger's conflict clause is
  // overridden by the statement that fires it (e.g. the strokes upsert).
  static String _queue(String surface) =>
      'INSERT INTO ink_text_queue (surface_id, version) '
      'VALUES ($surface, ${_nextVersion()}) '
      'ON CONFLICT (surface_id) DO UPDATE SET version = excluded.version;';

  static void _createTriggers(CommonDatabase db) {
    // Strokes → queue. Sync bookkeeping (`dirty`, versions) changes nothing.
    db.execute('''
      CREATE TRIGGER IF NOT EXISTS ink_text_strokes_ai AFTER INSERT ON strokes BEGIN
        ${_queue('NEW.surface_id')}
      END''');
    db.execute('''
      CREATE TRIGGER IF NOT EXISTS ink_text_strokes_au AFTER UPDATE ON strokes
      WHEN OLD.deleted IS NOT NEW.deleted OR OLD.surface_id IS NOT NEW.surface_id
        OR OLD.points IS NOT NEW.points BEGIN
        ${_queue('NEW.surface_id')}
        ${_queue('OLD.surface_id')}
      END''');
    db.execute('''
      CREATE TRIGGER IF NOT EXISTS ink_text_strokes_ad AFTER DELETE ON strokes BEGIN
        ${_queue('OLD.surface_id')}
      END''');

    // ink_text → search_docs.
    const kind = SearchSchema.handwriting;
    db.execute('''
      CREATE TRIGGER IF NOT EXISTS search_ink_text_ai AFTER INSERT ON ink_text
      WHEN NEW.text <> '' BEGIN
        DELETE FROM search_docs WHERE kind = '$kind' AND ref_id = CAST(NEW.id AS TEXT);
        INSERT INTO search_docs (kind, ref_id, surface_id, body)
        VALUES ('$kind', CAST(NEW.id AS TEXT), NEW.surface_id, NEW.text);
      END''');
    db.execute('''
      CREATE TRIGGER IF NOT EXISTS search_ink_text_au AFTER UPDATE ON ink_text BEGIN
        DELETE FROM search_docs WHERE kind = '$kind' AND ref_id = CAST(OLD.id AS TEXT);
        INSERT INTO search_docs (kind, ref_id, surface_id, body)
        SELECT '$kind', CAST(NEW.id AS TEXT), NEW.surface_id, NEW.text WHERE NEW.text <> '';
      END''');
    db.execute('''
      CREATE TRIGGER IF NOT EXISTS search_ink_text_ad AFTER DELETE ON ink_text BEGIN
        DELETE FROM search_docs WHERE kind = '$kind' AND ref_id = CAST(OLD.id AS TEXT);
      END''');
  }

  /// The `search_docs` rows for all recognised lines (used by
  /// [SearchSchema.rebuild]; nothing if the table does not exist yet).
  static void indexAll(CommonDatabase db) {
    if (!exists(db)) return;
    db.execute('''
      INSERT OR REPLACE INTO search_docs (kind, ref_id, surface_id, body)
      SELECT '${SearchSchema.handwriting}', CAST(id AS TEXT), surface_id, text
      FROM ink_text WHERE text <> '' ''');
  }

  static bool exists(CommonDatabase db) => db
      .select("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'ink_text'")
      .isNotEmpty;
}
