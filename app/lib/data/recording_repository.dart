import 'dart:convert';

import 'package:sqlite3/common.dart';

import '../domain/recording.dart';
import 'blob_store.dart';
import 'record_fields.dart';
import 'syncable.dart';
import 'syncable_table.dart';

/// Persists audio recordings (collection `recordings`): one row per
/// recording of a notebook, referencing its audio blobs.
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

  /// Creation times (epoch ms, sorted) of the live strokes and elements of
  /// [notebookId] (its canvas or pages) made between [from] and [to]: when
  /// the ink of a recording was written.
  List<int> contentTimes(String notebookId, {required int from, required int to}) {
    const surfaces =
        '(SELECT ?1 UNION ALL SELECT id FROM pages WHERE notebook_id = ?1 AND deleted = 0)';
    return db
        .select(
          'SELECT created_at FROM strokes WHERE surface_id IN $surfaces AND deleted = 0 '
          'AND created_at BETWEEN ?2 AND ?3 '
          'UNION ALL SELECT created_at FROM elements WHERE surface_id IN $surfaces '
          'AND deleted = 0 AND created_at BETWEEN ?2 AND ?3 ORDER BY 1',
          [notebookId, from, to],
        )
        .map((r) => r['created_at'] as int)
        .toList();
  }

  /// Adds a recording of [notebookId] whose audio is [parts] — or, given
  /// [id], replaces that recording's audio, keeping its title (a recording
  /// still being made gains parts as they are finished).
  Recording save({
    String? id,
    required String notebookId,
    required List<RecordingPart> parts,
    required String mime,
    required String title,
    required List<RecordingSegment> segments,
    String waveform = '',
  }) {
    assert(segments.isNotEmpty && parts.isNotEmpty);
    final existing = id == null ? null : get(id);
    final recordingId = id ?? clock.newId();
    final recording = Recording(
      id: recordingId,
      notebookId: notebookId,
      parts: parts,
      durationMs: parts.fold(0, (sum, p) => sum + p.durationMs),
      startedAt: segments.first.startedAt,
      title: existing?.title ?? title,
      mime: mime,
      updatedAt: id == null ? clock.nowMs() : nextVersion(recordingId),
      waveform: waveform,
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

  /// Keeps only audio [startMs]…[endMs] of recording [id] (non-destructive:
  /// `0` and its duration undo it); returns the updated recording.
  Recording? trim(String id, int startMs, int endMs) {
    final current = get(id);
    if (current == null) return null;
    assert(0 <= startMs && startMs <= endMs && endMs <= current.durationMs);
    final updated = current.copyWith(
      trimStartMs: startMs,
      trimEndMs: endMs,
      updatedAt: nextVersion(id),
    );
    _write(updated, deviceId: deviceId, dirty: true);
    return updated;
  }

  /// Tombstones recording [id]. Its blob stays until garbage collection
  /// (see `LocalBlobGc`) finds it unreferenced for long enough.
  void delete(String id) => _tombstone(id);

  /// Tombstones several recordings at once.
  void deleteAll(Iterable<String> ids) => database.transaction(() => ids.forEach(_tombstone));

  /// Tombstones every recording of [notebookId] (notebook deletion), at
  /// [version] if given.
  void deleteAllOf(String notebookId, {int? version}) {
    final ids = db
        .select('SELECT id FROM recordings WHERE notebook_id = ? AND deleted = 0', [notebookId])
        .map((r) => r['id'] as String)
        .toList();
    database.transaction(() {
      for (final id in ids) {
        _tombstone(id, version);
      }
    });
  }

  void _tombstone(String id, [int? version]) => db.execute(
    'UPDATE recordings SET deleted = 1, dirty = 1, updated_at = ?, device_id = ? WHERE id = ?',
    [version ?? nextVersion(id), deviceId, id],
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
              'audio': jsonDecode(row['audio'] as String),
              'durationMs': row['duration_ms'],
              'startedAt': row['started_at'],
              'title': row['title'],
              'mime': row['mime'],
              'segments': jsonDecode(row['segments'] as String),
              'waveform': row['waveform'],
              'trimStartMs': row['trim_start_ms'],
              'trimEndMs': row['trim_end_ms'],
            },
    );
  }

  @override
  void writeRemote(SyncRecord record) {
    if (record.deleted) {
      db.execute(
        '''
        INSERT INTO recordings (id, notebook_id, audio, duration_ms, started_at, title, mime,
                                segments, updated_at, device_id, deleted, dirty)
        VALUES (?, '', '[]', 0, 0, '', '', '[]', ?, ?, 1, 0)
        ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at,
          device_id = excluded.device_id, deleted = 1, dirty = 0''',
        [record.id, record.updatedAt, record.deviceId],
      );
      return;
    }
    final f = RecordFields(record);
    final parts = [
      for (final p in f.list('audio'))
        switch (RecordingPart.tryParse(p)) {
          final part? when BlobStore.isValidId(part.blob) => part,
          _ => f.invalid('audio'),
        },
    ];
    if (parts.isEmpty) f.invalid('audio');
    final segments = [
      for (final s in f.list('segments')) RecordingSegment.tryParse(s) ?? f.invalid('segments'),
    ];
    final waveform = f.string('waveform');
    if (waveform.isNotEmpty && !BlobStore.isValidId(waveform)) f.invalid('waveform');
    final durationMs = f.integer('durationMs');
    final trimStart = f.integer('trimStartMs');
    final trimEnd = f.integer('trimEndMs');
    if (trimStart < 0 || trimStart > trimEnd) f.invalid('trimStartMs');
    if (trimEnd > durationMs) f.invalid('trimEndMs');
    _write(
      Recording(
        id: record.id,
        notebookId: f.string('notebookId'),
        parts: parts,
        durationMs: durationMs,
        startedAt: f.integer('startedAt'),
        title: f.string('title'),
        mime: f.string('mime'),
        updatedAt: record.updatedAt,
        waveform: waveform,
        segments: segments,
        trimStartMs: trimStart,
        trimEndMs: trimEnd,
      ),
      deviceId: record.deviceId,
      dirty: false,
    );
  }

  void _write(Recording r, {required String deviceId, required bool dirty}) {
    db.execute(
      '''
      INSERT OR REPLACE INTO recordings (id, notebook_id, audio, duration_ms, started_at, title,
                                         mime, segments, waveform, trim_start_ms, trim_end_ms,
                                         updated_at, device_id, deleted, dirty)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)''',
      [
        r.id,
        r.notebookId,
        jsonEncode([for (final p in r.parts) p.toJson()]),
        r.durationMs,
        r.startedAt,
        r.title,
        r.mime,
        jsonEncode([for (final s in r.segments) s.toJson()]),
        r.waveform,
        r.trimStartMs,
        r.trimEndMs,
        r.updatedAt,
        deviceId,
        dirty ? 1 : 0,
      ],
    );
  }

  static Recording _rowToRecording(Row row) {
    final raw = jsonDecode(row['segments'] as String);
    final audio = jsonDecode(row['audio'] as String) as List;
    return Recording(
      id: row['id'] as String,
      notebookId: row['notebook_id'] as String,
      parts: audio.map(RecordingPart.tryParse).nonNulls.toList(),
      durationMs: row['duration_ms'] as int,
      startedAt: row['started_at'] as int,
      title: row['title'] as String,
      mime: row['mime'] as String,
      updatedAt: row['updated_at'] as int,
      waveform: row['waveform'] as String,
      segments: raw is List ? raw.map(RecordingSegment.tryParse).nonNulls.toList() : null,
      trimStartMs: row['trim_start_ms'] as int,
      trimEndMs: row['trim_end_ms'] as int,
    );
  }
}
