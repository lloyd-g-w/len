import 'package:sqlite3/common.dart';

import '../domain/folder.dart';
import 'name_order.dart';
import 'record_fields.dart';
import 'syncable.dart';
import 'syncable_table.dart';

/// Persists the library's nested folders (collection `folders`).
///
/// Concurrent moves on two devices can, in theory, produce a parent cycle or
/// a folder whose parent was deleted. Readers therefore treat any folder
/// whose ancestor chain does not reach the top level cleanly as top-level
/// (see [effectiveParentOf]), so nothing ever becomes unreachable.
class FolderRepository extends SyncableTable {
  FolderRepository(super.database, {required super.deviceId, super.clock});

  @override
  String get collection => 'folders';

  @override
  String get table => 'folders';

  /// All live folders, sorted by name as notebooks are ([NameOrder]).
  List<Folder> list() =>
      db.select('SELECT * FROM folders WHERE deleted = 0').map(_rowToFolder).toList()
        ..sort(NameOrder.comparator((f) => f.name, (f) => f.id));

  Folder? get(String id) {
    final rows = db.select('SELECT * FROM folders WHERE id = ? AND deleted = 0', [id]);
    return rows.isEmpty ? null : _rowToFolder(rows.first);
  }

  /// Live folders directly inside [parentId] (null = top level), by name.
  List<Folder> childrenOf(String? parentId) {
    final all = list();
    final byId = {for (final f in all) f.id: f};
    return [
      for (final f in all)
        if (effectiveParentOf(f, byId) == parentId) f,
    ];
  }

  /// The parent [folder] is displayed under: its stored parent, or null when
  /// that parent is missing/deleted or [folder] is part of a parent cycle.
  static String? effectiveParentOf(Folder folder, Map<String, Folder> byId) {
    final parent = folder.parentId;
    if (parent == null || !byId.containsKey(parent)) return null;
    String? cursor = parent;
    for (var steps = 0; cursor != null && steps <= byId.length; steps++) {
      if (cursor == folder.id) return null; // Cycle through this folder.
      cursor = byId[cursor]?.parentId;
    }
    return parent;
  }

  /// The folders from the top level down to [folderId] (inclusive), for
  /// breadcrumbs. Empty if [folderId] is null or unknown.
  List<Folder> pathTo(String? folderId) {
    if (folderId == null) return const [];
    final byId = {for (final f in list()) f.id: f};
    final path = <Folder>[];
    var current = byId[folderId];
    while (current != null && path.length <= byId.length) {
      path.insert(0, current);
      final parent = effectiveParentOf(current, byId);
      current = parent == null ? null : byId[parent];
    }
    return path;
  }

  /// [folderId] and all folders nested inside it.
  Set<String> subtreeOf(String folderId) {
    final all = list();
    final byId = {for (final f in all) f.id: f};
    final result = <String>{folderId};
    var grew = true;
    while (grew) {
      grew = false;
      for (final f in all) {
        final parent = effectiveParentOf(f, byId);
        if (parent != null && result.contains(parent) && result.add(f.id)) grew = true;
      }
    }
    return result;
  }

  /// Creates a folder inside [parentId] (null = top level).
  Folder create({required String name, String? parentId, required int color}) {
    final now = clock.nowMs();
    final folder = Folder(
      id: clock.newId(),
      name: name,
      parentId: parentId,
      color: color,
      createdAt: now,
      updatedAt: now,
    );
    _write(folder, deviceId: deviceId, dirty: true);
    return folder;
  }

  /// Saves name/colour/parent changes.
  Folder update(Folder folder) {
    final updated = folder.copyWith(updatedAt: nextVersion(folder.id));
    _write(updated, deviceId: deviceId, dirty: true);
    return updated;
  }

  /// Whether [folderId] may be moved into [parentId] (not into itself or one
  /// of its own descendants).
  bool canMove(String folderId, String? parentId) =>
      parentId == null || !subtreeOf(folderId).contains(parentId);

  /// Moves a folder into [parentId] (null = top level). Returns null if the
  /// move would create a cycle or the folder is gone.
  Folder? move(String folderId, String? parentId) {
    final folder = get(folderId);
    if (folder == null || !canMove(folderId, parentId)) return null;
    return update(folder.copyWith(parentId: parentId));
  }

  /// Tombstones [folderId] and every folder nested in it; returns their ids
  /// so callers can deal with the notebooks they contained (none if
  /// [folderId] is gone already: its notebooks show at the top level).
  Set<String> delete(String folderId) {
    if (get(folderId) == null) return const {};
    final ids = subtreeOf(folderId);
    final now = clock.nowMs();
    database.transaction(() {
      for (final id in ids) {
        db.execute(
          'UPDATE folders SET deleted = 1, dirty = 1, updated_at = ?, device_id = ? '
          'WHERE id = ?',
          [nextVersion(id, now), deviceId, id],
        );
      }
    });
    return ids;
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
              'name': row['name'],
              'parentId': row['parent_id'],
              'color': row['color'],
              'createdAt': row['created_at'],
            },
    );
  }

  @override
  void writeRemote(SyncRecord record) {
    if (record.deleted) {
      db.execute(
        '''
        INSERT INTO folders (id, name, parent_id, color, created_at,
                             updated_at, device_id, deleted, dirty)
        VALUES (?, '', NULL, 0, 0, ?, ?, 1, 0)
        ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at,
          device_id = excluded.device_id, deleted = 1, dirty = 0''',
        [record.id, record.updatedAt, record.deviceId],
      );
      return;
    }
    final f = RecordFields(record);
    _write(
      Folder(
        id: record.id,
        name: f.string('name'),
        parentId: f.stringOrNull('parentId'),
        color: f.integer('color'),
        createdAt: f.integer('createdAt'),
        updatedAt: record.updatedAt,
      ),
      deviceId: record.deviceId,
      dirty: false,
    );
  }

  void _write(Folder f, {required String deviceId, required bool dirty}) {
    db.execute(
      '''
      INSERT OR REPLACE INTO folders (id, name, parent_id, color, created_at,
                                      updated_at, device_id, deleted, dirty)
      VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?)''',
      [f.id, f.name, f.parentId, f.color, f.createdAt, f.updatedAt, deviceId, dirty ? 1 : 0],
    );
  }

  static Folder _rowToFolder(Row row) => Folder(
    id: row['id'] as String,
    name: row['name'] as String,
    parentId: row['parent_id'] as String?,
    color: row['color'] as int,
    createdAt: row['created_at'] as int,
    updatedAt: row['updated_at'] as int,
  );
}
