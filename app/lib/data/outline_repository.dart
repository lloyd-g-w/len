import 'package:sqlite3/common.dart';

import '../domain/outline/outline_entry.dart';
import 'record_fields.dart';
import 'syncable.dart';
import 'syncable_table.dart';

/// Persists notebooks' own outlines (collection `outline`).
class OutlineRepository extends SyncableTable {
  OutlineRepository(super.database, {required super.deviceId, super.clock});

  @override
  String get collection => 'outline';

  @override
  String get table => 'outline';

  /// Live entries of notebook [notebookId] (unordered; see `OutlineTree`).
  List<OutlineEntry> entriesOf(String notebookId) => db
      .select('SELECT * FROM outline WHERE notebook_id = ? AND deleted = 0', [notebookId])
      .map(_rowToEntry)
      .toList();

  OutlineEntry? get(String id) {
    final rows = db.select('SELECT * FROM outline WHERE id = ? AND deleted = 0', [id]);
    return rows.isEmpty ? null : _rowToEntry(rows.first);
  }

  /// Adds an entry for page [pageId] of [notebookId].
  OutlineEntry add({
    required String notebookId,
    required String pageId,
    required String title,
    String? parentId,
  }) {
    final entry = OutlineEntry(
      id: clock.newId(),
      notebookId: notebookId,
      pageId: pageId,
      parentId: parentId,
      title: title,
      createdAt: clock.nowMs(),
    );
    _write(entry, updatedAt: clock.nowMs(), deviceId: deviceId, dirty: true);
    return entry;
  }

  /// Stores a changed entry (title, parent or page).
  void update(OutlineEntry entry) =>
      _write(entry, updatedAt: nextVersion(entry.id), deviceId: deviceId, dirty: true);

  /// Deletes entry [id]; its children move up to its parent.
  void delete(String id) => database.transaction(() {
    final entry = get(id);
    if (entry == null) return;
    for (final child
        in db
            .select('SELECT * FROM outline WHERE parent_id = ? AND deleted = 0', [id])
            .map(_rowToEntry)
            .toList()) {
      update(child.copyWith(parentId: entry.parentId));
    }
    _tombstone(id);
  });

  /// Tombstones every entry of notebook [notebookId] (deleted forever), at
  /// [version] if given.
  void deleteAllOf(String notebookId, {int? version}) => database.transaction(() {
    for (final r in db.select('SELECT id FROM outline WHERE notebook_id = ? AND deleted = 0', [
      notebookId,
    ])) {
      _tombstone(r['id'] as String, version);
    }
  });

  /// Copies the outline of notebook [from] to [to] under new ids, mapping
  /// pages through [pages] (original page id → copy); with [onlyPages],
  /// only the entries of those pages (one whose parent stays behind goes
  /// to the top level). Returns the new entries' ids.
  List<String> copyAll(
    String from,
    String to,
    Map<String, String> pages, {
    bool onlyPages = false,
  }) => database.transaction(() {
    final entries = [
      for (final e in entriesOf(from))
        if (!onlyPages || pages.containsKey(e.pageId)) e,
    ];
    final ids = {for (final e in entries) e.id: clock.newId()};
    for (final e in entries) {
      _write(
        OutlineEntry(
          id: ids[e.id]!,
          notebookId: to,
          pageId: pages[e.pageId] ?? e.pageId,
          parentId: ids[e.parentId],
          title: e.title,
          createdAt: e.createdAt,
        ),
        updatedAt: clock.nowMs(),
        deviceId: deviceId,
        dirty: true,
      );
    }
    return ids.values.toList();
  });

  void _tombstone(String id, [int? version]) => db.execute(
    'UPDATE outline SET deleted = 1, dirty = 1, updated_at = ?, device_id = ? WHERE id = ?',
    [version ?? nextVersion(id), deviceId, id],
  );

  /// The notebook of entry [id] (live or not), for sync notifications.
  String? notebookOf(String id) {
    final rows = database.select('SELECT notebook_id FROM outline WHERE id = ?', [id]);
    return rows.isEmpty ? null : rows.first['notebook_id'] as String;
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
              'notebookId': row['notebook_id'],
              'pageId': row['page_id'],
              'parentId': row['parent_id'],
              'title': row['title'],
              'createdAt': row['created_at'],
            },
    );
  }

  @override
  void writeRemote(SyncRecord record) {
    if (record.deleted) {
      db.execute(
        '''
        INSERT INTO outline (id, notebook_id, page_id, parent_id, title, created_at,
                             updated_at, device_id, deleted, dirty)
        VALUES (?, '', '', NULL, '', 0, ?, ?, 1, 0)
        ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at,
          device_id = excluded.device_id, deleted = 1, dirty = 0''',
        [record.id, record.updatedAt, record.deviceId],
      );
      return;
    }
    final f = RecordFields(record);
    final notebookId = f.string('notebookId'), pageId = f.string('pageId');
    if (notebookId.isEmpty) f.invalid('notebookId');
    if (pageId.isEmpty) f.invalid('pageId');
    _write(
      OutlineEntry(
        id: record.id,
        notebookId: notebookId,
        pageId: pageId,
        parentId: f.stringOrNull('parentId'),
        title: f.string('title'),
        createdAt: f.integer('createdAt'),
      ),
      updatedAt: record.updatedAt,
      deviceId: record.deviceId,
      dirty: false,
    );
  }

  void _write(
    OutlineEntry e, {
    required int updatedAt,
    required String deviceId,
    required bool dirty,
  }) {
    db.execute(
      '''
      INSERT OR REPLACE INTO outline (id, notebook_id, page_id, parent_id, title, created_at,
                                      updated_at, device_id, deleted, dirty)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?)''',
      [
        e.id,
        e.notebookId,
        e.pageId,
        e.parentId,
        e.title,
        e.createdAt,
        updatedAt,
        deviceId,
        dirty ? 1 : 0,
      ],
    );
  }

  static OutlineEntry _rowToEntry(Row row) => OutlineEntry(
    id: row['id'] as String,
    notebookId: row['notebook_id'] as String,
    pageId: row['page_id'] as String,
    parentId: row['parent_id'] as String?,
    title: row['title'] as String,
    createdAt: row['created_at'] as int,
  );
}
