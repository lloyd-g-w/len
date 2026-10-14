import 'dart:convert';

import 'package:sqlite3/common.dart';

import '../domain/notebook_style.dart';
import 'record_fields.dart';
import 'syncable.dart';
import 'syncable_table.dart';

/// Persists the user's notebook styles (collection `notebook_styles`): named
/// [NotebookChoice]s the new-notebook sheet offers, one of them perhaps the
/// default for new notebooks.
class NotebookStyleRepository extends SyncableTable {
  NotebookStyleRepository(super.database, {required super.deviceId, super.clock});

  @override
  String get collection => 'notebook_styles';

  @override
  String get table => 'notebook_styles';

  /// Live styles, oldest first (a new one joins the end of the row).
  List<NotebookStyle> list() => db
      .select('SELECT * FROM notebook_styles WHERE deleted = 0 ORDER BY created_at, id')
      .map(_rowToStyle)
      .toList();

  NotebookStyle? get(String id) {
    final rows = db.select('SELECT * FROM notebook_styles WHERE id = ? AND deleted = 0', [id]);
    return rows.isEmpty ? null : _rowToStyle(rows.first);
  }

  /// The style new notebooks start as, or null. Should two devices each
  /// have marked one before syncing, the one marked last wins.
  NotebookStyle? defaultStyle() {
    final rows = db.select(
      'SELECT * FROM notebook_styles WHERE deleted = 0 AND is_default = 1 '
      'ORDER BY updated_at DESC, id LIMIT 1',
    );
    return rows.isEmpty ? null : _rowToStyle(rows.first);
  }

  /// Saves [choice] as a style named [name].
  NotebookStyle create({required String name, required NotebookChoice choice}) {
    final style = NotebookStyle(
      id: clock.newId(),
      name: name,
      choice: choice,
      createdAt: clock.nowMs(),
    );
    _write(style, updatedAt: clock.nowMs(), deviceId: deviceId, dirty: true);
    return style;
  }

  void rename(String id, String name) => _update(id, 'name = ?', [name]);

  /// Makes [id] the default style ([isDefault]) or no longer the default;
  /// any other default stops being one.
  void setDefault(String id, {required bool isDefault}) => database.transaction(() {
    if (isDefault) {
      for (final row in db.select(
        'SELECT id FROM notebook_styles WHERE deleted = 0 AND is_default = 1 AND id <> ?',
        [id],
      )) {
        _update(row['id'] as String, 'is_default = 0', const []);
      }
    }
    _update(id, 'is_default = ?', [if (isDefault) 1 else 0]);
  });

  void delete(String id) => _update(id, 'deleted = 1', const []);

  void _update(String id, String set, List<Object?> args) => db.execute(
    'UPDATE notebook_styles SET $set, dirty = 1, updated_at = ?, device_id = ? WHERE id = ?',
    [...args, nextVersion(id), deviceId, id],
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
              'style': jsonDecode(row['style'] as String),
              'isDefault': row['is_default'] == 1,
              'createdAt': row['created_at'],
            },
    );
  }

  @override
  void writeRemote(SyncRecord record) {
    if (record.deleted) {
      db.execute(
        '''
        INSERT INTO notebook_styles (id, name, style, is_default, created_at,
                                     updated_at, device_id, deleted, dirty)
        VALUES (?, '', '{}', 0, 0, ?, ?, 1, 0)
        ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at,
          device_id = excluded.device_id, deleted = 1, dirty = 0''',
        [record.id, record.updatedAt, record.deviceId],
      );
      return;
    }
    final f = RecordFields(record);
    _write(
      NotebookStyle(
        id: record.id,
        name: f.string('name'),
        choice: NotebookChoice.fromJson(f.object('style')) ?? f.invalid('style'),
        isDefault: f.boolean('isDefault'),
        createdAt: f.integer('createdAt'),
      ),
      updatedAt: record.updatedAt,
      deviceId: record.deviceId,
      dirty: false,
    );
  }

  void _write(
    NotebookStyle s, {
    required int updatedAt,
    required String deviceId,
    required bool dirty,
  }) {
    db.execute(
      '''
      INSERT OR REPLACE INTO notebook_styles (id, name, style, is_default, created_at,
                                              updated_at, device_id, deleted, dirty)
      VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?)''',
      [
        s.id,
        s.name,
        jsonEncode(s.choice.toJson()),
        if (s.isDefault) 1 else 0,
        s.createdAt,
        updatedAt,
        deviceId,
        if (dirty) 1 else 0,
      ],
    );
  }

  /// A stored row; a style the app can no longer read (it is checked when
  /// written) falls back to the defaults rather than failing the list.
  static NotebookStyle _rowToStyle(Row row) => NotebookStyle(
    id: row['id'] as String,
    name: row['name'] as String,
    choice:
        NotebookChoice.fromJson(jsonDecode(row['style'] as String) as Map<String, Object?>) ??
        const NotebookChoice(coverColor: 0xFF3B5BDB),
    isDefault: row['is_default'] == 1,
    createdAt: row['created_at'] as int,
  );
}
