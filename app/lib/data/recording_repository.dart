import 'dart:convert';

import 'package:sqlite3/common.dart';

import '../domain/recording.dart';
import 'blob_store.dart';
import 'syncable.dart';
import 'syncable_table.dart';

/// Persists audio recordings (collection `recordings`): one row per
/// recording of a notebook, referencing its audio blob.
class RecordingRepository extends SyncableTable {
  RecordingRepository(super.database, {required super.deviceId, super.clock});

  @override
  String get collection => 'recordings';

  @override
  String get table => 'recordings';

  /// Live recordings of [notebookId], oldest first.
  List<Recording> listOf(String notebookId) => db
      .select(
        'SELECT * FROM recordings WHERE notebook_id = ? AND deleted = 0 '
        'ORDER BY started_at, id',
        [notebookId],
      )
      .map(_rowToRecording)
      .toList();

  Recording? get(String id) {
    final rows = db.select('SELECT * FROM recordings WHERE id = ? AND deleted = 0', [id]);
    return rows.isEmpty ? null : _rowToRecording(rows.first);
  }

  /// The notebook of recording [id] (deleted rows included), if known.
  String? notebookOf(String id) =>
      db.select('SELECT notebook_id FROM recordings WHERE id = ?', [id]).firstOrNull?['notebook_id']
          as String?;

  /// Adds a recording of [notebookId] whose audio is blob [blob].
  Recording create({
    required String notebookId,
    required String blob,
    required String mime,
    required String title,
    required List<RecordingSegment> segments,
  }) {
    assert(segments.isNotEmpty);
    final recording = Recording(
      id: clock.newId(),
      notebookId: notebookId,
      blob: blob,
      durationMs: segments.fold(0, (sum, s) => sum + s.durationMs),
      startedAt: segments.first.startedAt,
      title: title,
      mime: mime,
      updatedAt: clock.nowMs(),
      segments: segments,
    );
    _write(recording, deviceId: deviceId, dirty: true);
    return recording;
  }

  /// Renames recording [id]; returns the updated recording.
  Recording? rename(String id, String title) {
    final current = get(id);
    if (current == null) return null;
    final updated = current.copyWith(title: title, updatedAt: nextVersion(id));
    _write(updated, deviceId: deviceId, dirty: true);
    return updated;
  }

  /// Tombstones recording [id] (its blob stays, see "Blobs" in the sync
  /// protocol: blobs are never deleted).
  void delete(String id) => _tombstone(id);

  /// Tombstones every recording of [notebookId] (notebook deletion).
  void deleteAllOf(String notebookId) {
    final ids = db
        .select('SELECT id FROM recordings WHERE notebook_id = ? AND deleted = 0', [notebookId])
        .map((r) => r['id'] as String)
        .toList();
    database.transaction(() => ids.forEach(_tombstone));
  }

  void _tombstone(String id) => db.execute(
    'UPDATE recordings SET deleted = 1, dirty = 1, updated_at = ?, device_id = ? WHERE id = ?',
    [nextVersion(id), deviceId, id],
  );

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
          : {
              'notebookId': row['notebook_id'],
              'blob': row['blob'],
              'durationMs': row['duration_ms'],
              'startedAt': row['started_at'],
              'title': row['title'],
              'mime': row['mime'],
              'segments': jsonDecode(row['segments'] as String),
            },
    );
  }

  @override
  void writeRemote(SyncRecord record) {
    if (record.deleted) {
      db.execute(
        '''
        INSERT INTO recordings (id, notebook_id, blob, duration_ms, started_at, title, mime,
                                segments, updated_at, device_id, deleted, dirty)
        VALUES (?, '', '', 0, 0, '', '', '[]', ?, ?, 1, 0)
        ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at,
          device_id = excluded.device_id, deleted = 1, dirty = 0''',
        [record.id, record.updatedAt, record.deviceId],
      );
      return;
    }
    final d = record.data!;
    final notebookId = d['notebookId'];
    final blob = d['blob'];
    final durationMs = d['durationMs'];
    final startedAt = d['startedAt'];
    if (notebookId is! String ||
        blob is! String ||
        !BlobStore.isValidId(blob) ||
        durationMs is! int ||
        startedAt is! int) {
      throw FormatException('Malformed recording ${record.id}');
    }
    final title = d['title'];
    final mime = d['mime'];
    final rawSegments = d['segments'];
    final segments = rawSegments is List
        ? rawSegments.map(RecordingSegment.tryParse).nonNulls.toList()
        : const <RecordingSegment>[];
    _write(
      Recording(
        id: record.id,
        notebookId: notebookId,
        blob: blob,
        durationMs: durationMs,
        startedAt: startedAt,
        title: title is String ? title : '',
        mime: mime is String ? mime : 'audio/mp4',
        updatedAt: record.updatedAt,
        segments: segments,
      ),
      deviceId: record.deviceId,
      dirty: false,
    );
  }

  void _write(Recording r, {required String deviceId, required bool dirty}) {
    db.execute(
      '''
      INSERT OR REPLACE INTO recordings (id, notebook_id, blob, duration_ms, started_at, title,
                                         mime, segments, updated_at, device_id, deleted, dirty)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)''',
      [
        r.id,
        r.notebookId,
        r.blob,
        r.durationMs,
        r.startedAt,
        r.title,
        r.mime,
        jsonEncode([for (final s in r.segments) s.toJson()]),
        r.updatedAt,
        deviceId,
        dirty ? 1 : 0,
      ],
    );
  }

  static Recording _rowToRecording(Row row) {
    final raw = jsonDecode(row['segments'] as String);
    return Recording(
      id: row['id'] as String,
      notebookId: row['notebook_id'] as String,
      blob: row['blob'] as String,
      durationMs: row['duration_ms'] as int,
      startedAt: row['started_at'] as int,
      title: row['title'] as String,
      mime: row['mime'] as String,
      updatedAt: row['updated_at'] as int,
      segments: raw is List ? raw.map(RecordingSegment.tryParse).nonNulls.toList() : null,
    );
  }
}
