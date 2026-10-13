import 'dart:convert';

import 'package:sqlite3/common.dart';

import 'record_fields.dart';
import 'syncable.dart';
import 'syncable_table.dart';

/// The handwriting of one surface as a device with a recogniser read it.
class RecognisedText {
  const RecognisedText({required this.language, required this.lines, required this.updatedAt});

  /// The language (BCP 47) it was recognised in.
  final String language;

  /// Text per line, by the line's stroke key (`InkLine.key`), top to bottom.
  final Map<String, String> lines;

  /// The record's version (ms, the writing device's clock).
  final int updatedAt;
}

/// Recognised handwriting, synced (collection `recognised_text`, one record
/// per surface, id = the surface id), so devices without a recogniser can
/// search what an Android device read.
///
/// Records hold only text per line, keyed by the hash of the line's strokes:
/// every device clusters its own strokes (`InkClustering`, deterministic),
/// uses the text of lines whose key matches — boxes come from its own
/// clustering — and ignores the rest, so text of edited or erased ink is
/// never shown, whoever erased it. Only devices with a recogniser write
/// records (`HandwritingIndexer`); remote writes queue the surface for
/// indexing (trigger in `InkTextSchema`).
class RecognisedTextRepository extends SyncableTable {
  RecognisedTextRepository(super.database, {required super.deviceId, super.clock});

  @override
  String get collection => 'recognised_text';

  @override
  String get table => 'recognised_text';

  /// The live record of [surfaceId], if any.
  RecognisedText? read(String surfaceId) {
    final rows = db.select(
      'SELECT language, lines, updated_at FROM recognised_text WHERE id = ? AND deleted = 0',
      [surfaceId],
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return RecognisedText(
      language: r['language'] as String,
      lines: {
        for (final pair in jsonDecode(r['lines'] as String) as List<Object?>)
          (pair as List<Object?>)[0] as String: pair[1] as String,
      },
      updatedAt: r['updated_at'] as int,
    );
  }

  /// Stores what this device recognised on [surfaceId].
  void write(String surfaceId, String language, Map<String, String> lines) => _write(
    surfaceId,
    language,
    _encode(lines),
    updatedAt: nextVersion(surfaceId),
    deviceId: deviceId,
    dirty: true,
  );

  /// Syncs what this device read on [surfaceId] ([lines]: text by line
  /// key, in [language]) when the record is missing or lacks lines, or holds
  /// lines that are gone; tombstones it when no lines are left. Other
  /// differences (another reading of the same strokes) are left alone, so
  /// two devices never take turns rewriting a record — except that a
  /// reading in a language the user chose here ([languageChangedAt]) after
  /// the record was written replaces it.
  void publish(
    String surfaceId,
    String language,
    Map<String, String> lines, {
    required int languageChangedAt,
  }) {
    final current = read(surfaceId);
    if (lines.isEmpty) {
      if (current != null) delete(surfaceId);
      return;
    }
    final outdated =
        current == null ||
        current.lines.length != lines.length ||
        !lines.keys.every(current.lines.containsKey) ||
        (current.language != language && current.updatedAt < languageChangedAt);
    if (outdated) write(surfaceId, language, lines);
  }

  /// Tombstones the record of [surfaceId] (no handwriting left on it).
  void delete(String surfaceId) => db.execute(
    'UPDATE recognised_text SET deleted = 1, dirty = 1, updated_at = ?, device_id = ? '
    'WHERE id = ? AND deleted = 0',
    [nextVersion(surfaceId), deviceId, surfaceId],
  );

  static String _encode(Map<String, String> lines) => jsonEncode([
    for (final MapEntry(:key, :value) in lines.entries) [key, value],
  ]);

  // ---------------------------------------------------------------------------
  // Sync

  @override
  SyncRecord rowToRecord(Row row) {
    final deleted = row['deleted'] == 1;
    return SyncRecord(
      collection: collection,
      id: row['id'] as String,
      updatedAt: row['updated_at'] as int,
      deviceId: row['device_id'] as String,
      deleted: deleted,
      data: deleted
          ? null
          : {'language': row['language'], 'lines': jsonDecode(row['lines'] as String)},
    );
  }

  @override
  void writeRemote(SyncRecord record) {
    if (record.deleted) {
      db.execute(
        '''
        INSERT INTO recognised_text (id, language, lines, updated_at, device_id, deleted, dirty)
        VALUES (?, '', '[]', ?, ?, 1, 0)
        ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at,
          device_id = excluded.device_id, deleted = 1, dirty = 0''',
        [record.id, record.updatedAt, record.deviceId],
      );
      return;
    }
    final f = RecordFields(record);
    final language = f.string('language');
    if (language.isEmpty) f.invalid('language');
    final lines = <String, String>{};
    for (final pair in f.list('lines')) {
      if (pair is! List<Object?> || pair.length != 2) f.invalid('lines');
      final [key, text] = pair;
      if (key is! String || key.isEmpty || text is! String) f.invalid('lines');
      lines[key] = text;
    }
    _write(
      record.id,
      language,
      _encode(lines),
      updatedAt: record.updatedAt,
      deviceId: record.deviceId,
      dirty: false,
    );
  }

  // An upsert (not INSERT OR REPLACE), so the queueing triggers see updates.
  void _write(
    String id,
    String language,
    String lines, {
    required int updatedAt,
    required String deviceId,
    required bool dirty,
  }) => db.execute(
    '''
    INSERT INTO recognised_text (id, language, lines, updated_at, device_id, deleted, dirty)
    VALUES (?, ?, ?, ?, ?, 0, ?)
    ON CONFLICT(id) DO UPDATE SET language = excluded.language, lines = excluded.lines,
      updated_at = excluded.updated_at, device_id = excluded.device_id, deleted = 0,
      dirty = excluded.dirty''',
    [id, language, lines, updatedAt, deviceId, dirty ? 1 : 0],
  );
}
