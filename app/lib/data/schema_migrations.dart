import 'package:sqlite3/common.dart';

import 'chunk_digest_migration.dart';
import 'initial_schema.dart';
import 'search/ink_text_schema.dart';

/// The ordered schema migrations `AppDatabase` applies (`PRAGMA
/// user_version` counts those applied). Version 1 creates the whole schema
/// ([InitialSchema]). Future schema changes **append** a migration; never
/// edit one that has shipped.
abstract final class SchemaMigrations {
  /// The digest of the schema [all] produce (`SchemaCheck.digestOf`): a
  /// database found in it is checked without building a fresh schema to
  /// compare with. `app_database_test` fails with the new value when a
  /// migration changes the schema.
  static const String shapeDigest =
      '370fed3aaeef016ea043375bebe829071c9945fa2037c0d16faea06016309eef';

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
    _tombstonePayloadIndexes,
    _notebookStyles,
    _freedBlobs,
    _textAlignStartEnd,
    _deletionBases,
    _versions,
    _versionTables,
  ];

  /// Version 17: version records name table blobs (docs/SYNC_PROTOCOL.md,
  /// "Version history"). `blob_links` (local) notes the blobs a reference
  /// blob names, so uploads and garbage collection follow them
  /// (`BlobLinks`); the pack cache is emptied, so surfaces are packed again
  /// in pack format 2.
  static void _versionTables(CommonDatabase db) {
    db.execute('''
      CREATE TABLE blob_links (
        parent TEXT NOT NULL,
        child  TEXT NOT NULL,
        PRIMARY KEY (parent, child)
      ) WITHOUT ROWID''');
    db.execute('CREATE INDEX blob_links_by_child ON blob_links(child)');
    db.execute('DELETE FROM version_packs');
  }

  /// Version 16: version history (docs/SYNC_PROTOCOL.md, "Version
  /// history"). `versions` holds the synced versions (the record `data`
  /// whole, with the columns queries need); `version_packs` (local, never
  /// synced) remembers each surface's packs by its change mark, so a new
  /// version re-packs only surfaces written since.
  static void _versions(CommonDatabase db) {
    db.execute('''
      CREATE TABLE versions (
        id          TEXT PRIMARY KEY NOT NULL,
        notebook_id TEXT NOT NULL,
        created_at  INTEGER NOT NULL,
        kind        TEXT NOT NULL,
        name        TEXT,
        size        INTEGER NOT NULL,
        data        TEXT NOT NULL,
        updated_at  INTEGER NOT NULL,
        device_id   TEXT NOT NULL,
        deleted     INTEGER NOT NULL DEFAULT 0,
        dirty       INTEGER NOT NULL DEFAULT 1
      )''');
    db.execute('CREATE INDEX versions_by_notebook ON versions(notebook_id, created_at)');
    db.execute('''
      CREATE TABLE version_packs (
        surface_id TEXT PRIMARY KEY NOT NULL,
        mark       TEXT NOT NULL,
        ink        TEXT NOT NULL,
        items      TEXT NOT NULL,
        blobs      TEXT NOT NULL,
        strokes    INTEGER NOT NULL,
        size       INTEGER NOT NULL
      ) WITHOUT ROWID''');
  }

  /// Version 15: which edit the content of a row edited in place comes
  /// from, and what its deletion knew (see `SyncableTable.editedInPlace`;
  /// docs/SYNC_PROTOCOL.md, "Deletion conflicts"). `origin_at` /
  /// `origin_device`: the version of the edit whose content the row holds,
  /// valid while `origin_for` is the row's `updated_at` (else the row's own
  /// version is: so any local write makes the row an edit of its own); set
  /// when an edit is kept over a deletion or a row brought back. `base_at` /
  /// `base_device` on a tombstone: the origin of what the deletion replaced.
  /// Triggers note both when a live row is deleted, however that is done,
  /// and keep a tombstone's origin across new versions of it.
  static void _deletionBases(CommonDatabase db) {
    for (final table in const ['elements', 'recordings', 'outline']) {
      for (final column in const [
        'base_at INTEGER',
        'base_device TEXT',
        'origin_at INTEGER',
        'origin_device TEXT',
        'origin_for INTEGER NOT NULL DEFAULT 0',
      ]) {
        db.execute('ALTER TABLE $table ADD COLUMN $column');
      }
      const valid = 'OLD.origin_for = OLD.updated_at AND OLD.origin_at IS NOT NULL';
      db.execute('''
        CREATE TRIGGER ${table}_deleted AFTER UPDATE OF deleted ON $table
        WHEN OLD.deleted = 0 AND NEW.deleted = 1 BEGIN
          UPDATE $table SET
            origin_at = CASE WHEN $valid THEN OLD.origin_at ELSE OLD.updated_at END,
            origin_device = CASE WHEN $valid THEN OLD.origin_device ELSE OLD.device_id END,
            origin_for = NEW.updated_at
          WHERE rowid = NEW.rowid;
          UPDATE $table SET base_at = origin_at, base_device = origin_device
          WHERE rowid = NEW.rowid;
        END''');
      db.execute('''
        CREATE TRIGGER ${table}_tombstone_versions AFTER UPDATE OF updated_at ON $table
        WHEN OLD.deleted = 1 AND NEW.deleted = 1 AND $valid BEGIN
          UPDATE $table SET origin_for = NEW.updated_at WHERE rowid = NEW.rowid;
        END''');
    }
  }

  /// Version 14: text boxes align to their paragraphs' start or end
  /// (`left` → `start`, `right` → `end`; right-to-left text). The record
  /// version is bumped so synced boxes are sent again in the new format.
  static void _textAlignStartEnd(CommonDatabase db) {
    db.execute('''
      UPDATE elements
      SET data = json_set(data, '\$.align',
            CASE json_extract(data, '\$.align') WHEN 'right' THEN 'end' ELSE 'start' END),
          updated_at = updated_at + 1,
          dirty = 1
      WHERE type = 'text' AND deleted = 0 AND json_valid(data) AND json_type(data) = 'object'
        AND json_extract(data, '\$.align') IN ('left', 'right')
    ''');
  }

  /// Version 13: files whose copies here Free up removed (`FreedBlobs`;
  /// local only).
  static void _freedBlobs(CommonDatabase db) {
    db.execute('''
      CREATE TABLE freed_blobs (
        sha256   TEXT PRIMARY KEY NOT NULL,
        mime     TEXT NOT NULL,
        freed_at INTEGER NOT NULL
      )''');
  }

  /// Version 12: the user's notebook styles (collection `notebook_styles`,
  /// see `NotebookStyleRepository`); `style` is `NotebookChoice.toJson`.
  static void _notebookStyles(CommonDatabase db) {
    db.execute('''
      CREATE TABLE notebook_styles (
        id          TEXT PRIMARY KEY NOT NULL,
        name        TEXT NOT NULL,
        style       TEXT NOT NULL,
        is_default  INTEGER NOT NULL DEFAULT 0,
        created_at  INTEGER NOT NULL,
        updated_at  INTEGER NOT NULL,
        device_id   TEXT NOT NULL,
        deleted     INTEGER NOT NULL DEFAULT 0,
        dirty       INTEGER NOT NULL DEFAULT 1
      )''');
  }

  /// Version 11: tombstones that still keep their payload, by version, so
  /// dropping the old payloads (`TombstonePayloads.purge`, at the daily
  /// blob garbage collection) is an index range instead of a scan of every
  /// stroke. Rows leave these indexes once purged.
  static void _tombstonePayloadIndexes(CommonDatabase db) {
    db.execute(
      'CREATE INDEX strokes_tombstone_payloads ON strokes(updated_at) '
      'WHERE deleted = 1 AND length(points) > 0',
    );
    db.execute(
      'CREATE INDEX elements_tombstone_payloads ON elements(updated_at) '
      "WHERE deleted = 1 AND data <> '{}'",
    );
  }

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
