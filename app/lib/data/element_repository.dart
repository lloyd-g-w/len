import 'dart:convert';
import 'dart:ui';

import 'package:sqlite3/common.dart';

import '../domain/chunk_digest.dart';
import '../domain/chunk_grid.dart';
import '../domain/link_target.dart';
import '../domain/stroke_chunks.dart';
import '../domain/surface_element.dart';
import '../domain/text/text_record.dart';
import 'record_fields.dart';
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

  /// Every live element on [surfaceId].
  List<SurfaceElement> allOn(String surfaceId) => db
      .select('SELECT * FROM elements WHERE surface_id = ? AND deleted = 0', [surfaceId])
      .map(StrokeQueries.rowToElement)
      .nonNulls
      .toList();

  /// Inserts or updates elements (also revives deleted ones on redo).
  void save(Iterable<SurfaceElement> elements) {
    final now = clock.nowMs();
    database.transaction(() {
      for (final e in elements) {
        _upsert(e, updatedAt: nextVersion(e.id, now), deviceId: deviceId, dirty: true);
      }
    });
  }

  /// Tombstones elements by id, all at [version] if given.
  void delete(Iterable<String> ids, {int? version}) {
    final now = clock.nowMs();
    database.transaction(() {
      for (final id in ids) {
        _tombstone(id, updatedAt: version ?? nextVersion(id, now), deviceId: deviceId, dirty: true);
      }
    });
  }

  /// Tombstones every element on the given surfaces (e.g. a deleted notebook),
  /// all at [version] if given.
  void deleteSurfaces(Iterable<String> surfaceIds, {int? version}) =>
      tombstoneSurfaces(surfaceIds, chunkTable: 'element_chunks', version: version);

  /// Brings back tombstoned elements whose data is still kept.
  @override
  void revive(Iterable<String> ids) {
    final now = clock.nowMs();
    for (final id in ids) {
      final rows = db.select(
        "SELECT * FROM elements WHERE id = ? AND deleted = 1 AND data <> '{}'",
        [id],
      );
      final element = rows.isEmpty ? null : StrokeQueries.rowToElement(rows.first);
      if (element == null) continue; // Its data was purged.
      _upsert(element, updatedAt: nextVersion(id, now), deviceId: deviceId, dirty: true);
    }
  }

  /// Drops the data of elements tombstoned before [before] (ms): they can
  /// no longer be revived (see `TombstonePayloads`), at most [limit] (-1:
  /// all); returns how many.
  int purgeTombstones(int before, {int limit = -1}) {
    db.execute(
      "UPDATE elements SET data = '{}' WHERE rowid IN (SELECT rowid FROM elements "
      "WHERE deleted = 1 AND updated_at < ? AND data <> '{}' LIMIT ?)",
      [before, limit],
    );
    return db.updatedRows;
  }

  /// Points the live links that lead to a page in [pages] (old page id →
  /// new page id) at the new page in notebook [notebookId] (pages moved
  /// there). Returns the links as they were: [save] them to take it back.
  List<SurfaceElement> retargetLinks(Map<String, String> pages, String notebookId) {
    if (pages.isEmpty) return const [];
    final before = <SurfaceElement>[];
    database.transaction(() {
      final rows = db.select('SELECT * FROM elements WHERE type = ? AND deleted = 0', [
        ElementType.link.name,
      ]);
      final moved = <SurfaceElement>[];
      for (final link in rows.map(StrokeQueries.rowToElement).nonNulls) {
        final target = LinkElements.targetOf(link);
        if (target is! PageLinkTarget) continue;
        final page = pages[target.pageId];
        if (page == null) continue;
        before.add(link);
        final to = PageLinkTarget(notebookId: notebookId, pageId: page);
        moved.add(link.copyWith(data: {...link.data, 'target': to.toJson()}));
      }
      save(moved);
    });
    return before;
  }

  /// Surface id of a stored element (live or tombstoned), if known.
  String? surfaceOf(String elementId) {
    final rows = database.select('SELECT surface_id FROM elements WHERE id = ?', [elementId]);
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
      _elementFromRecord(record),
      updatedAt: record.updatedAt,
      deviceId: record.deviceId,
      dirty: false,
    );
  }

  /// Parses a live record; throws [FormatException] when malformed.
  static SurfaceElement _elementFromRecord(SyncRecord record) {
    final f = RecordFields(record);
    final type = f.string('type');
    if (type.isEmpty) f.invalid('type');
    final w = f.number('w');
    final h = f.number('h');
    if (w < 0) f.invalid('w');
    if (h < 0) f.invalid('h');
    final element = SurfaceElement(
      id: record.id,
      surfaceId: f.string('surfaceId'),
      type: type,
      rect: Rect.fromLTWH(f.number('x'), f.number('y'), w, h),
      rotation: f.number('rotation'),
      z: f.number('z'),
      createdAt: f.integer('createdAt'),
      data: f.object('data'),
    );
    if (!WorldLimits.accepts(element.bounds)) f.invalid('bounds');
    if (element.knownType == ElementType.text) TextRecord.parse(element.data);
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
    database.execute(
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
    // A known element keeps its data for a while (see `DeletionConflicts`).
    database.execute(
      '''
      INSERT INTO elements (id, surface_id, type, x, y, w, h, data,
                            created_at, updated_at, device_id, deleted, dirty)
      VALUES (?, '', '', 0, 0, 0, 0, '{}', 0, ?, ?, 1, ?)
      ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at,
        device_id = excluded.device_id, deleted = 1, dirty = excluded.dirty''',
      [id, updatedAt, deviceId, dirty ? 1 : 0],
    );
    database.execute('DELETE FROM element_chunks WHERE element_id = ?', [id]);
  }

  void _reindex(SurfaceElement e) {
    database.execute('DELETE FROM element_chunks WHERE element_id = ?', [e.id]);
    final digest = ChunkDigest.ofElement(e);
    for (final key in ElementChunks.of(e)) {
      database.execute(
        'INSERT OR IGNORE INTO element_chunks (surface_id, cx, cy, element_id, digest) '
        'VALUES (?, ?, ?, ?, ?)',
        [e.surfaceId, key.x, key.y, e.id, digest],
      );
    }
  }
}
