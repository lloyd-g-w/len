import 'dart:ui';

import 'package:sqlite3/common.dart';

import '../data/blob_store.dart';
import '../domain/templates/user_template.dart';
import 'record_fields.dart';
import 'syncable.dart';
import 'syncable_table.dart';

/// Persists the user's own templates (collection `templates`). Their images
/// are blobs; pages made from a template reference the blob directly, so
/// deleting a template never changes existing pages.
class TemplateRepository extends SyncableTable {
  TemplateRepository(super.database, {required super.deviceId, super.clock});

  @override
  String get collection => 'templates';

  @override
  String get table => 'templates';

  /// Live templates, newest first.
  List<UserTemplate> list() => db
      .select('SELECT * FROM templates WHERE deleted = 0 ORDER BY created_at DESC, id')
      .map(_rowToTemplate)
      .toList();

  UserTemplate? get(String id) {
    final rows = db.select('SELECT * FROM templates WHERE id = ? AND deleted = 0', [id]);
    return rows.isEmpty ? null : _rowToTemplate(rows.first);
  }

  /// Adds a template showing image blob [blob] on pages of [size].
  UserTemplate create({required String name, required String blob, required Size size}) {
    final template = UserTemplate(
      id: clock.newId(),
      name: name,
      blob: blob,
      width: size.width,
      height: size.height,
      createdAt: clock.nowMs(),
    );
    _write(template, updatedAt: clock.nowMs(), deviceId: deviceId, dirty: true);
    return template;
  }

  void rename(String id, String name) => db.execute(
    'UPDATE templates SET name = ?, dirty = 1, updated_at = ?, device_id = ? WHERE id = ?',
    [name, nextVersion(id), deviceId, id],
  );

  void delete(String id) => db.execute(
    'UPDATE templates SET deleted = 1, dirty = 1, updated_at = ?, device_id = ? WHERE id = ?',
    [nextVersion(id), deviceId, id],
  );

  /// Undoes [delete].
  void restore(String id) => db.execute(
    'UPDATE templates SET deleted = 0, dirty = 1, updated_at = ?, device_id = ? WHERE id = ?',
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
              'name': row['name'],
              'blob': row['blob'],
              'width': row['width'],
              'height': row['height'],
              'createdAt': row['created_at'],
            },
    );
  }

  @override
  void writeRemote(SyncRecord record) {
    if (record.deleted) {
      db.execute(
        '''
        INSERT INTO templates (id, name, blob, width, height, created_at,
                               updated_at, device_id, deleted, dirty)
        VALUES (?, '', '', 0, 0, 0, ?, ?, 1, 0)
        ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at,
          device_id = excluded.device_id, deleted = 1, dirty = 0''',
        [record.id, record.updatedAt, record.deviceId],
      );
      return;
    }
    final f = RecordFields(record);
    final blob = f.string('blob');
    if (!BlobStore.isValidId(blob)) f.invalid('blob');
    final width = f.number('width'), height = f.number('height');
    if (width <= 0) f.invalid('width');
    if (height <= 0) f.invalid('height');
    _write(
      UserTemplate(
        id: record.id,
        name: f.string('name'),
        blob: blob,
        width: width,
        height: height,
        createdAt: f.integer('createdAt'),
      ),
      updatedAt: record.updatedAt,
      deviceId: record.deviceId,
      dirty: false,
    );
  }

  void _write(
    UserTemplate t, {
    required int updatedAt,
    required String deviceId,
    required bool dirty,
  }) {
    db.execute(
      '''
      INSERT OR REPLACE INTO templates (id, name, blob, width, height, created_at,
                                        updated_at, device_id, deleted, dirty)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?)''',
      [t.id, t.name, t.blob, t.width, t.height, t.createdAt, updatedAt, deviceId, dirty ? 1 : 0],
    );
  }

  static UserTemplate _rowToTemplate(Row row) => UserTemplate(
    id: row['id'] as String,
    name: row['name'] as String,
    blob: row['blob'] as String,
    width: (row['width'] as num).toDouble(),
    height: (row['height'] as num).toDouble(),
    createdAt: row['created_at'] as int,
  );
}
