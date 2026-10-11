import 'package:sqlite3/common.dart';

import '../domain/tag.dart';
import 'record_fields.dart';
import 'syncable.dart';
import 'syncable_table.dart';
import 'tagging_repository.dart';

/// Persists the user's tags (collection `tags`). Which notebooks and pages
/// carry a tag is kept in [taggings] (collection `taggings`).
class TagRepository extends SyncableTable {
  TagRepository(super.database, {required super.deviceId, super.clock})
    : taggings = TaggingRepository(database, deviceId: deviceId, clock: clock);

  /// Tag assignments; synced as their own collection.
  final TaggingRepository taggings;

  @override
  String get collection => 'tags';

  @override
  String get table => 'tags';

  /// Longest tag name accepted from the UI.
  static const maxNameLength = 40;

  /// Live tags, by name (case-insensitive).
  List<Tag> list() => db
      .select('SELECT * FROM tags WHERE deleted = 0 ORDER BY name COLLATE NOCASE, id')
      .map(_rowToTag)
      .toList();

  Tag? get(String id) {
    final rows = db.select('SELECT * FROM tags WHERE id = ? AND deleted = 0', [id]);
    return rows.isEmpty ? null : _rowToTag(rows.first);
  }

  /// The live tag named [name] (ignoring case and surrounding space).
  Tag? byName(String name) {
    final rows = db.select(
      'SELECT * FROM tags WHERE deleted = 0 AND name = ? COLLATE NOCASE ORDER BY created_at, id',
      [name.trim()],
    );
    return rows.isEmpty ? null : _rowToTag(rows.first);
  }

  /// Creates a tag, or returns the existing one of that name.
  Tag create({required String name, required int color}) {
    final existing = byName(name);
    if (existing != null) return existing;
    final tag = Tag(id: clock.newId(), name: name.trim(), color: color, createdAt: clock.nowMs());
    _write(tag, updatedAt: clock.nowMs(), deviceId: deviceId, dirty: true);
    return tag;
  }

  /// Renames or recolours a tag.
  void update(Tag tag) =>
      _write(tag, updatedAt: nextVersion(tag.id), deviceId: deviceId, dirty: true);

  /// Deletes a tag and takes it off everything it was on.
  void delete(String id) => database.transaction(() {
    db.execute(
      'UPDATE tags SET deleted = 1, dirty = 1, updated_at = ?, device_id = ? WHERE id = ?',
      [nextVersion(id), deviceId, id],
    );
    taggings.removeTag(id);
  });

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
          : {'name': row['name'], 'color': row['color'], 'createdAt': row['created_at']},
    );
  }

  @override
  void writeRemote(SyncRecord record) {
    if (record.deleted) {
      db.execute(
        '''
        INSERT INTO tags (id, name, color, created_at, updated_at, device_id, deleted, dirty)
        VALUES (?, '', 0, 0, ?, ?, 1, 0)
        ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at,
          device_id = excluded.device_id, deleted = 1, dirty = 0''',
        [record.id, record.updatedAt, record.deviceId],
      );
      return;
    }
    final f = RecordFields(record);
    final name = f.string('name');
    if (name.trim().isEmpty) f.invalid('name');
    _write(
      Tag(id: record.id, name: name, color: f.integer('color'), createdAt: f.integer('createdAt')),
      updatedAt: record.updatedAt,
      deviceId: record.deviceId,
      dirty: false,
    );
  }

  void _write(Tag t, {required int updatedAt, required String deviceId, required bool dirty}) {
    db.execute(
      '''
      INSERT OR REPLACE INTO tags (id, name, color, created_at, updated_at, device_id,
                                   deleted, dirty)
      VALUES (?, ?, ?, ?, ?, ?, 0, ?)''',
      [t.id, t.name, t.color, t.createdAt, updatedAt, deviceId, dirty ? 1 : 0],
    );
  }

  static Tag _rowToTag(Row row) => Tag(
    id: row['id'] as String,
    name: row['name'] as String,
    color: row['color'] as int,
    createdAt: row['created_at'] as int,
  );
}
