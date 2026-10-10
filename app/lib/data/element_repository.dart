import 'dart:convert';
import 'dart:ui';

import 'package:sqlite3/common.dart';

import '../domain/chunk_grid.dart';
import '../domain/stroke_chunks.dart';
import '../domain/surface_element.dart';
import 'stroke_queries.dart';
import 'syncable.dart';
import 'syncable_table.dart';

/// Persists surface elements (text boxes, later images) with the same
/// sparse chunk index as strokes, so they load lazily with the ink around
/// the viewport.
class ElementRepository extends SyncableTable {
  ElementRepository(super.database, {required super.deviceId, super.clock});

  @override
  String get collection => 'elements';

  @override
  String get table => 'elements';

  late final StrokeQueries _queries = StrokeQueries(db);

  /// Chunks within [range] that contain at least one live element.
  List<ChunkKey> populatedChunks(String surfaceId, ChunkRange range) =>
      _queries.populatedElementChunks(surfaceId, range);

  /// Live elements on [surfaceId] touching any of [keys].
  List<SurfaceElement> loadChunks(String surfaceId, List<ChunkKey> keys) =>
      _queries.loadElementChunks(surfaceId, keys);

  /// Inserts or updates elements (also revives deleted ones on redo).
  void save(Iterable<SurfaceElement> elements) {
    final now = clock.nowMs();
    database.transaction(() {
      for (final e in elements) {
        _upsert(e, updatedAt: nextVersion(e.id, now), deviceId: deviceId, dirty: true);
      }
    });
  }

  /// Tombstones elements by id.
  void delete(Iterable<String> ids) {
    final now = clock.nowMs();
    database.transaction(() {
      for (final id in ids) {
        _tombstone(id, updatedAt: nextVersion(id, now), deviceId: deviceId, dirty: true);
      }
    });
  }

  /// Tombstones every element on the given surfaces (e.g. a deleted notebook).
  void deleteSurfaces(Iterable<String> surfaceIds) {
    database.transaction(() {
      for (final surfaceId in surfaceIds) {
        delete(
          db
              .select('SELECT id FROM elements WHERE surface_id = ? AND deleted = 0', [surfaceId])
              .map((r) => r['id'] as String)
              .toList(),
        );
      }
    });
  }

  /// Surface id of a stored element (live or tombstoned), if known.
  String? surfaceOf(String elementId) {
    final rows = db.select('SELECT surface_id FROM elements WHERE id = ?', [elementId]);
    return rows.isEmpty ? null : rows.first['surface_id'] as String;
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
              'type': row['type'],
              'x': row['x'],
              'y': row['y'],
              'w': row['w'],
              'h': row['h'],
              'rotation': row['rotation'],
              'z': row['z'],
              'createdAt': row['created_at'],
              'data':
                  StrokeQueries.decodeElementData(row['data'] as String) ??
                  const <String, Object?>{},
            },
    );
  }

  @override
  void writeRemote(SyncRecord record) {
    if (record.deleted) {
      _tombstone(record.id, updatedAt: record.updatedAt, deviceId: record.deviceId, dirty: false);
      return;
    }
    _upsert(
      elementFromData(record.id, record.data!),
      updatedAt: record.updatedAt,
      deviceId: record.deviceId,
      dirty: false,
    );
  }

  /// Parses a wire payload; throws [FormatException] when malformed.
  static SurfaceElement elementFromData(String id, Map<String, Object?> data) {
    final surfaceId = data['surfaceId'];
    final type = data['type'];
    final x = data['x'], y = data['y'], w = data['w'], h = data['h'];
    final createdAt = data['createdAt'];
    if (surfaceId is! String ||
        type is! String ||
        type.isEmpty ||
        x is! num ||
        y is! num ||
        w is! num ||
        h is! num ||
        createdAt is! int) {
      throw FormatException('Malformed element $id');
    }
    final rect = Rect.fromLTWH(x.toDouble(), y.toDouble(), w.toDouble(), h.toDouble());
    if (!rect.isFinite || w < 0 || h < 0) throw FormatException('Invalid element geometry $id');
    final rotation = data['rotation'];
    final z = data['z'];
    final payload = data['data'];
    final element = SurfaceElement(
      id: id,
      surfaceId: surfaceId,
      type: type,
      rect: rect,
      rotation: rotation is num && rotation.isFinite ? rotation.toDouble() : 0,
      z: z is num && z.isFinite ? z.toDouble() : createdAt.toDouble(),
      createdAt: createdAt,
      data: payload is Map<String, Object?> ? payload : const {},
    );
    if (!WorldLimits.accepts(element.bounds)) {
      throw FormatException('Element $id is out of bounds');
    }
    return element;
  }

  // ---------------------------------------------------------------------------
  // Internals

  void _upsert(
    SurfaceElement e, {
    required int updatedAt,
    required String deviceId,
    required bool dirty,
  }) {
    db.execute(
      '''
      INSERT INTO elements (id, surface_id, type, x, y, w, h, rotation, z, data,
                            created_at, updated_at, device_id, deleted, dirty)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)
      ON CONFLICT(id) DO UPDATE SET
        surface_id = excluded.surface_id, type = excluded.type,
        x = excluded.x, y = excluded.y, w = excluded.w, h = excluded.h,
        rotation = excluded.rotation, z = excluded.z, data = excluded.data,
        created_at = excluded.created_at, updated_at = excluded.updated_at,
        device_id = excluded.device_id, deleted = 0, dirty = excluded.dirty''',
      [
        e.id,
        e.surfaceId,
        e.type,
        e.rect.left,
        e.rect.top,
        e.rect.width,
        e.rect.height,
        e.rotation,
        e.z,
        jsonEncode(e.data),
        e.createdAt,
        updatedAt,
        deviceId,
        dirty ? 1 : 0,
      ],
    );
    _reindex(e);
  }

  void _tombstone(
    String id, {
    required int updatedAt,
    required String deviceId,
    required bool dirty,
  }) {
    // A bare tombstone for never-seen rows stops older versions reviving them.
    db.execute(
      '''
      INSERT INTO elements (id, surface_id, type, x, y, w, h, data,
                            created_at, updated_at, device_id, deleted, dirty)
      VALUES (?, '', '', 0, 0, 0, 0, '{}', 0, ?, ?, 1, ?)
      ON CONFLICT(id) DO UPDATE SET
        data = '{}', updated_at = excluded.updated_at,
        device_id = excluded.device_id, deleted = 1, dirty = excluded.dirty''',
      [id, updatedAt, deviceId, dirty ? 1 : 0],
    );
    db.execute('DELETE FROM element_chunks WHERE element_id = ?', [id]);
  }

  void _reindex(SurfaceElement e) {
    db.execute('DELETE FROM element_chunks WHERE element_id = ?', [e.id]);
    final insert = db.prepare(
      'INSERT OR IGNORE INTO element_chunks (surface_id, cx, cy, element_id) VALUES (?, ?, ?, ?)',
    );
    try {
      for (final key in ElementChunks.of(e)) {
        insert.execute([e.surfaceId, key.x, key.y, e.id]);
      }
    } finally {
      insert.close();
    }
  }
}
