import 'package:sqlite3/common.dart';

import 'chunk_digest_migration.dart';
import 'initial_schema.dart';
import 'search/ink_text_schema.dart';

/// The ordered schema migrations `AppDatabase` applies (`PRAGMA
/// user_version` counts those applied). Version 1 creates the whole schema
/// ([InitialSchema]). Future schema changes **append** a migration; never
/// edit one that has shipped.
abstract final class SchemaMigrations {
  /// Index i migrates from version i to i + 1.
  static final List<void Function(CommonDatabase)> all = [
    InitialSchema.create,
    _templates,
    _recordingWaveforms,
    _organise,
    _recordingParts,
    _recordingTrim,
    _notebookPaperData,
    _strokeEndStyles,
    _recognisedText,
    ChunkDigestMigration.migrate,
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
}
