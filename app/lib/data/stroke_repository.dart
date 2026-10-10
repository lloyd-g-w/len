import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:sqlite3/common.dart';

import '../domain/chunk_grid.dart';
import '../domain/stroke.dart';
import '../domain/stroke_chunks.dart';
import 'stroke_codec.dart';
import 'stroke_queries.dart';
import 'stroke_reader.dart';
import 'syncable.dart';
import 'syncable_table.dart';

/// Persists strokes and maintains the sparse per-surface chunk index used
/// to load only the visible part of a surface.
class StrokeRepository extends SyncableTable implements StrokeReader {
  StrokeRepository(super.database, {required super.deviceId, super.clock});

  /// Widest stroke accepted from sync (far above any pen's range). Guards
  /// against corrupt records whose bounds would index millions of chunks.
  static const double maxWidth = 1000;

  @override
  String get collection => 'strokes';

  @override
  String get table => 'strokes';

  late final StrokeQueries _queries = StrokeQueries(db);

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
  Map<ChunkKey, int> chunkDensity(String surfaceId) => _queries.chunkDensity(surfaceId);

  @override
  Rect? contentBounds(String surfaceId) => _queries.contentBounds(surfaceId);

  /// Inserts new strokes, or revives previously deleted ones (redo).
  void save(Iterable<Stroke> strokes) {
    final now = clock.nowMs();
    database.transaction(() {
      for (final s in strokes) {
        _upsert(s, updatedAt: nextVersion(s.id, now), deviceId: deviceId, dirty: true);
      }
    });
  }

  /// Tombstones strokes by id.
  void delete(Iterable<String> ids) {
    final now = clock.nowMs();
    database.transaction(() {
      for (final id in ids) {
        _tombstone(id, updatedAt: nextVersion(id, now), deviceId: deviceId, dirty: true);
      }
    });
  }

  /// Tombstones every stroke on the given surfaces (e.g. a deleted notebook).
  void deleteSurfaces(Iterable<String> surfaceIds) {
    final now = clock.nowMs();
    database.transaction(() {
      for (final surfaceId in surfaceIds) {
        final ids = db
            .select('SELECT id FROM strokes WHERE surface_id = ? AND deleted = 0', [surfaceId])
            .map((r) => r['id'] as String)
            .toList();
        for (final id in ids) {
          _tombstone(id, updatedAt: nextVersion(id, now), deviceId: deviceId, dirty: true);
        }
      }
    });
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
    final stroke = _strokeFromData(record.id, record.data!);
    _upsert(stroke, updatedAt: record.updatedAt, deviceId: record.deviceId, dirty: false);
  }

  /// Surface id of a stored stroke (live or tombstoned), if known.
  String? surfaceOf(String strokeId) {
    final rows = db.select('SELECT surface_id FROM strokes WHERE id = ?', [strokeId]);
    return rows.isEmpty ? null : rows.first['surface_id'] as String;
  }

  // ---------------------------------------------------------------------------
  // Internals

  void _upsert(Stroke s, {required int updatedAt, required String deviceId, required bool dirty}) {
    db.execute(
      '''
      INSERT INTO strokes (id, surface_id, tool, color, width, points,
                           created_at, updated_at, device_id, deleted, dirty, style)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        surface_id = excluded.surface_id, tool = excluded.tool,
        color = excluded.color, width = excluded.width, style = excluded.style,
        points = excluded.points, created_at = excluded.created_at,
        updated_at = excluded.updated_at, device_id = excluded.device_id,
        deleted = 0, dirty = excluded.dirty''',
      [
        s.id,
        s.surfaceId,
        s.tool.name,
        s.color,
        s.width,
        StrokeCodec.encode(s.points),
        s.createdAt,
        updatedAt,
        deviceId,
        dirty ? 1 : 0,
        jsonEncode(s.style.toJson()),
      ],
    );
    _reindex(s);
  }

  void _tombstone(
    String id, {
    required int updatedAt,
    required String deviceId,
    required bool dirty,
  }) {
    // Insert a bare tombstone if the stroke was never seen locally, so an
    // older live version arriving later cannot resurrect it.
    db.execute(
      '''
      INSERT INTO strokes (id, surface_id, tool, color, width, points,
                           created_at, updated_at, device_id, deleted, dirty)
      VALUES (?, '', 'pen', 0, 0, x'', 0, ?, ?, 1, ?)
      ON CONFLICT(id) DO UPDATE SET
        points = x'', updated_at = excluded.updated_at,
        device_id = excluded.device_id, deleted = 1, dirty = excluded.dirty''',
      [id, updatedAt, deviceId, dirty ? 1 : 0],
    );
    db.execute('DELETE FROM stroke_chunks WHERE stroke_id = ?', [id]);
  }

  void _reindex(Stroke s) {
    db.execute('DELETE FROM stroke_chunks WHERE stroke_id = ?', [s.id]);
    final insert = db.prepare(
      'INSERT OR IGNORE INTO stroke_chunks (surface_id, cx, cy, stroke_id) '
      'VALUES (?, ?, ?, ?)',
    );
    try {
      for (final key in StrokeChunks.of(s)) {
        insert.execute([s.surfaceId, key.x, key.y, s.id]);
      }
    } finally {
      insert.close();
    }
  }

  static Stroke _strokeFromData(String id, Map<String, Object?> data) {
    final surfaceId = data['surfaceId'];
    final tool = data['tool'];
    final color = data['color'];
    final width = data['width'];
    final points = data['points'];
    final createdAt = data['createdAt'];
    if (surfaceId is! String ||
        tool is! String ||
        color is! int ||
        width is! num ||
        points is! String ||
        createdAt is! int) {
      throw FormatException('Malformed stroke $id');
    }
    final decoded = StrokeCodec.decode(base64Decode(points));
    if (decoded.isEmpty || !width.isFinite || width <= 0 || width > maxWidth) {
      throw FormatException('Invalid stroke geometry $id');
    }
    if (!WorldLimits.accepts(Stroke.computeBounds(decoded, width.toDouble()))) {
      throw FormatException('Stroke $id is out of bounds');
    }
    final inkTool = InkTool.parse(tool);
    return Stroke(
      id: id,
      surfaceId: surfaceId,
      tool: inkTool,
      color: color,
      width: width.toDouble(),
      points: decoded,
      createdAt: createdAt,
      // Older clients send no style; newer ones may add unknown fields.
      style: StrokeStyle.fromJson(data['style'], fallback: StrokeStyle.defaultsFor(inkTool)),
    );
  }
}
