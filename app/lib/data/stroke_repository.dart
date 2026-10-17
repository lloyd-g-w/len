import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:sqlite3/common.dart';

import '../domain/chunk_digest.dart';
import '../domain/chunk_grid.dart';
import '../domain/stroke.dart';
import 'stroke_queries.dart';
import 'stroke_reader.dart';
import 'stroke_row.dart';
import 'syncable.dart';
import 'syncable_table.dart';

/// Persists strokes and maintains the sparse per-surface chunk index used
/// to load only the visible part of a surface.
class StrokeRepository extends SyncableTable implements StrokeReader {
  StrokeRepository(super.database, {required super.deviceId, super.clock});

  @override
  String get collection => 'strokes';

  @override
  String get table => 'strokes';

  late final StrokeQueries _queries = StrokeQueries(db);

  /// The read-only queries on this repository's connection.
  StrokeQueries get queries => _queries;

  /// Chunks within [range] that contain at least one live stroke.
  List<ChunkKey> populatedChunks(String surfaceId, ChunkRange range) =>
      _queries.populatedChunks(surfaceId, range);

  /// Live strokes on [surfaceId] touching any of [keys].
  List<Stroke> loadChunks(String surfaceId, List<ChunkKey> keys) =>
      _queries.loadChunks(surfaceId, keys);

  @override
  ChunkLoad read(String surfaceId, ChunkRange range, {Set<ChunkKey> skip = const {}}) =>
      _queries.read(surfaceId, range, skip: skip);

  @override
  Map<ChunkKey, ChunkDigest> chunkDigests(String surfaceId, ChunkRange range) =>
      _queries.chunkDigests(surfaceId, range);

  @override
  Map<ChunkKey, int> chunkDensity(String surfaceId) => _queries.chunkDensity(surfaceId);

  @override
  Rect? contentBounds(String surfaceId) => _queries.contentBounds(surfaceId);

  /// Whether [surfaceId] has any live stroke or element (a quick query).
  bool hasContent(String surfaceId) => _queries.hasContent(surfaceId);

  /// Inserts new strokes, or revives previously deleted ones (redo).
  void save(Iterable<Stroke> strokes) {
    final now = clock.nowMs();
    final rows = [for (final s in strokes) StrokeRow.of(s)];
    if (rows.isEmpty) return;
    database.transaction(() {
      final versions = nextVersions([for (final r in rows) r.id], now);
      var i = 0;
      // Whole batches in one statement each, the rest one by one.
      for (; i + _rowsAtOnce <= rows.length; i += _rowsAtOnce) {
        database.execute(_putMany, [
          for (var k = i; k < i + _rowsAtOnce; k++)
            ..._values(rows[k], versions[k], deviceId, true),
        ]);
      }
      for (; i < rows.length; i++) {
        _put(rows[i], updatedAt: versions[i], deviceId: deviceId, dirty: true);
      }
      _reindexAll(rows);
    });
  }

  /// Tombstones strokes by id.
  void delete(Iterable<String> ids) {
    final now = clock.nowMs();
    final all = jsonEncode(ids.toSet().toList());
    if (all == '[]') return;
    // Stamped as nextVersion would stamp each: after now and the row's
    // version. Then a bare tombstone for a stroke never seen here, so an
    // older live version arriving later cannot resurrect it. A known
    // stroke keeps its points for a while, so a deletion that raced an
    // edit on another device can be undone (`DeletionConflicts`).
    database.transaction(() {
      database.execute(
        'UPDATE strokes SET updated_at = MAX(?, updated_at + 1), device_id = ?, deleted = 1, '
        'dirty = 1 WHERE id IN (SELECT value FROM json_each(?))',
        [now, deviceId, all],
      );
      database.execute(
        'INSERT OR IGNORE INTO strokes (id, surface_id, tool, color, width, points, '
        'created_at, updated_at, device_id, deleted, dirty) '
        "SELECT value, '', 'pen', 0, 0, x'', 0, ?, ?, 1, 1 FROM json_each(?)",
        [now, deviceId, all],
      );
      database.execute(
        'DELETE FROM stroke_chunks WHERE stroke_id IN (SELECT value FROM json_each(?))',
        [all],
      );
    });
  }

  /// Tombstones every stroke on the given surfaces (e.g. a deleted notebook),
  /// all at [version] if given (one deletion, see `NotebookRepository.delete`).
  void deleteSurfaces(Iterable<String> surfaceIds, {int? version}) =>
      tombstoneSurfaces(surfaceIds, chunkTable: 'stroke_chunks', version: version);

  /// Brings back tombstoned strokes whose points are still kept.
  @override
  void revive(Iterable<String> ids, {required int version}) {
    for (final id in ids) {
      final rows = db.select('SELECT * FROM strokes WHERE id = ? AND deleted = 1', [id]);
      final stroke = rows.isEmpty ? null : StrokeQueries.rowToStroke(rows.first);
      if (stroke == null) continue; // Its points were purged.
      if (version > (rows.first['updated_at'] as int)) {
        _upsert(stroke, updatedAt: version, deviceId: deviceId, dirty: true);
      }
    }
  }

  /// Drops the points of strokes tombstoned before [before] (ms): they can
  /// no longer be revived (see `TombstonePayloads`), at most [limit] (-1:
  /// all); returns how many.
  int purgeTombstones(int before, {int limit = -1}) {
    db.execute(
      'UPDATE strokes SET points = zeroblob(0) WHERE rowid IN (SELECT rowid FROM strokes '
      'WHERE deleted = 1 AND updated_at < ? AND length(points) > 0 LIMIT ?)',
      [before, limit],
    );
    return db.updatedRows;
  }

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
              'surfaceId': row['surface_id'],
              'tool': row['tool'],
              'color': row['color'],
              'width': row['width'],
              'points': base64Encode(row['points'] as Uint8List),
              'createdAt': row['created_at'],
              if (row['style'] case final String style) 'style': StrokeQueries.decodeStyle(style),
            },
    );
  }

  @override
  void writeRemote(SyncRecord record) {
    if (record.deleted) {
      _tombstone(record.id, updatedAt: record.updatedAt, deviceId: record.deviceId, dirty: false);
      return;
    }
    // Usually prepared while the page was decoded (see `decodePullPage`).
    final row = switch (record.prepared) {
      final StrokeRow row => row,
      _ => StrokeRow.fromRecord(record.id, record.data!),
    };
    _write(row, updatedAt: record.updatedAt, deviceId: record.deviceId, dirty: false);
  }

  /// Surface id of a stored stroke (live or tombstoned), if known.
  String? surfaceOf(String strokeId) {
    final rows = database.select('SELECT surface_id FROM strokes WHERE id = ?', [strokeId]);
    return rows.isEmpty ? null : rows.first['surface_id'] as String;
  }

  // ---------------------------------------------------------------------------
  // Internals

  void _upsert(Stroke s, {required int updatedAt, required String deviceId, required bool dirty}) =>
      _write(StrokeRow.of(s), updatedAt: updatedAt, deviceId: deviceId, dirty: dirty);

  void _write(
    StrokeRow s, {
    required int updatedAt,
    required String deviceId,
    required bool dirty,
  }) {
    _put(s, updatedAt: updatedAt, deviceId: deviceId, dirty: dirty);
    _reindex(s);
  }

  /// Writes row [s] without its chunk index.
  void _put(StrokeRow s, {required int updatedAt, required String deviceId, required bool dirty}) =>
      database.execute(_putOne, _values(s, updatedAt, deviceId, dirty));

  static const _insert = '''
      INSERT INTO strokes (id, surface_id, tool, color, width, points,
                           created_at, updated_at, device_id, deleted, dirty, style)
      VALUES ''';
  static const _row = '(?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?)';
  static const _onConflict = '''
      ON CONFLICT(id) DO UPDATE SET
        surface_id = excluded.surface_id, tool = excluded.tool,
        color = excluded.color, width = excluded.width, style = excluded.style,
        points = excluded.points, created_at = excluded.created_at,
        updated_at = excluded.updated_at, device_id = excluded.device_id,
        deleted = 0, dirty = excluded.dirty''';
  static const _putOne = '$_insert$_row$_onConflict';

  /// Rows [save] writes in one statement (a statement per row was most of
  /// the time of saving many).
  static const _rowsAtOnce = 16;
  static final _putMany = '$_insert${List.filled(_rowsAtOnce, _row).join(', ')}$_onConflict';

  /// The parameters of [_row] for [s].
  static List<Object?> _values(StrokeRow s, int updatedAt, String deviceId, bool dirty) => [
    s.id,
    s.surfaceId,
    s.tool,
    s.color,
    s.width,
    s.points,
    s.createdAt,
    updatedAt,
    deviceId,
    if (dirty) 1 else 0,
    s.style,
  ];

  void _tombstone(
    String id, {
    required int updatedAt,
    required String deviceId,
    required bool dirty,
  }) {
    // Insert a bare tombstone if the stroke was never seen locally, so an
    // older live version arriving later cannot resurrect it. A known stroke
    // keeps its points for a while, so a deletion that raced an edit on
    // another device can be undone (`DeletionConflicts`).
    database.execute(
      '''
      INSERT INTO strokes (id, surface_id, tool, color, width, points,
                           created_at, updated_at, device_id, deleted, dirty)
      VALUES (?, '', 'pen', 0, 0, x'', 0, ?, ?, 1, ?)
      ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at,
        device_id = excluded.device_id, deleted = 1, dirty = excluded.dirty''',
      [id, updatedAt, deviceId, dirty ? 1 : 0],
    );
    database.execute('DELETE FROM stroke_chunks WHERE stroke_id = ?', [id]);
  }

  /// [_reindex] for many rows in two statements (a statement per row and
  /// chunk was most of a commit of many lines).
  void _reindexAll(List<StrokeRow> rows) {
    database.execute(
      'DELETE FROM stroke_chunks WHERE stroke_id IN (SELECT value FROM json_each(?))',
      [
        jsonEncode([for (final s in rows) s.id]),
      ],
    );
    final entries = [
      for (final s in rows)
        for (final key in s.chunks) [s.surfaceId, key.x, key.y, s.id, ChunkDigest.ofStroke(s.id)],
    ];
    database.execute(
      'INSERT OR IGNORE INTO stroke_chunks (surface_id, cx, cy, stroke_id, digest) '
      'SELECT value ->> 0, value ->> 1, value ->> 2, value ->> 3, value ->> 4 FROM json_each(?)',
      [jsonEncode(entries)],
    );
  }

  void _reindex(StrokeRow s) {
    database.execute('DELETE FROM stroke_chunks WHERE stroke_id = ?', [s.id]);
    final digest = ChunkDigest.ofStroke(s.id);
    for (final key in s.chunks) {
      database.execute(
        'INSERT OR IGNORE INTO stroke_chunks (surface_id, cx, cy, stroke_id, digest) '
        'VALUES (?, ?, ?, ?, ?)',
        [s.surfaceId, key.x, key.y, s.id, digest],
      );
    }
  }
}
