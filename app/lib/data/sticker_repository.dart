import 'dart:convert';

import 'package:sqlite3/common.dart';

import '../domain/stickers/sticker.dart';
import 'record_fields.dart';
import 'sticker_codec.dart';
import 'syncable.dart';
import 'syncable_table.dart';

/// Persists the user's sticker library (collection `stickers`). Images in
/// stickers stay blobs (referenced from their element data), so they sync
/// and are kept like images on pages.
class StickerRepository extends SyncableTable {
  StickerRepository(super.database, {required super.deviceId, super.clock});

  @override
  String get collection => 'stickers';

  @override
  String get table => 'stickers';

  /// The category of stickers saved without one.
  static const defaultCategory = 'My stickers';

  /// Live stickers, newest first. Rows whose content cannot be read are
  /// left out.
  List<Sticker> list() => [
    for (final row in db.select(
      'SELECT * FROM stickers WHERE deleted = 0 ORDER BY created_at DESC, id',
    ))
      ?_rowToSticker(row),
  ];

  Sticker? get(String id) {
    final rows = db.select('SELECT * FROM stickers WHERE id = ? AND deleted = 0', [id]);
    return rows.isEmpty ? null : _rowToSticker(rows.first);
  }

  /// Saves [content] (laid out from the origin) as a new sticker.
  Sticker create({
    required String name,
    required String category,
    required StickerContent content,
  }) {
    final sticker = Sticker(
      id: clock.newId(),
      name: name,
      category: category.trim().isEmpty ? defaultCategory : category.trim(),
      content: content,
      createdAt: clock.nowMs(),
    );
    _write(
      sticker.id,
      sticker.name,
      sticker.category,
      jsonEncode(StickerCodec.encode(content)),
      sticker.createdAt,
      updatedAt: clock.nowMs(),
      deviceId: deviceId,
      dirty: true,
    );
    return sticker;
  }

  /// Renames a sticker or files it under another category.
  void update(String id, {String? name, String? category}) => db.execute(
    'UPDATE stickers SET name = COALESCE(?, name), category = COALESCE(?, category), '
    'dirty = 1, updated_at = ?, device_id = ? WHERE id = ?',
    [name, category, nextVersion(id), deviceId, id],
  );

  void delete(String id) => db.execute(
    'UPDATE stickers SET deleted = 1, dirty = 1, updated_at = ?, device_id = ? WHERE id = ?',
    [nextVersion(id), deviceId, id],
  );

  /// Undoes [delete].
  void restore(String id) => db.execute(
    'UPDATE stickers SET deleted = 0, dirty = 1, updated_at = ?, device_id = ? WHERE id = ?',
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
              'category': row['category'],
              'content': jsonDecode(row['content'] as String),
              'createdAt': row['created_at'],
            },
    );
  }

  @override
  void writeRemote(SyncRecord record) {
    if (record.deleted) {
      db.execute(
        '''
        INSERT INTO stickers (id, name, category, content, created_at,
                              updated_at, device_id, deleted, dirty)
        VALUES (?, '', '', '{}', 0, ?, ?, 1, 0)
        ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at,
          device_id = excluded.device_id, deleted = 1, dirty = 0''',
        [record.id, record.updatedAt, record.deviceId],
      );
      return;
    }
    final f = RecordFields(record);
    final content = f.object('content');
    final StickerContent decoded;
    try {
      decoded = StickerCodec.decode(content);
    } on FormatException {
      f.invalid('content');
    }
    if (decoded.isEmpty) f.invalid('content');
    final category = f.string('category');
    if (category.trim().isEmpty) f.invalid('category');
    _write(
      record.id,
      f.string('name'),
      category,
      jsonEncode(content),
      f.integer('createdAt'),
      updatedAt: record.updatedAt,
      deviceId: record.deviceId,
      dirty: false,
    );
  }

  void _write(
    String id,
    String name,
    String category,
    String content,
    int createdAt, {
    required int updatedAt,
    required String deviceId,
    required bool dirty,
  }) {
    db.execute(
      '''
      INSERT OR REPLACE INTO stickers (id, name, category, content, created_at,
                                       updated_at, device_id, deleted, dirty)
      VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?)''',
      [id, name, category, content, createdAt, updatedAt, deviceId, dirty ? 1 : 0],
    );
  }

  static Sticker? _rowToSticker(Row row) {
    try {
      return Sticker(
        id: row['id'] as String,
        name: row['name'] as String,
        category: row['category'] as String,
        content: StickerCodec.decode(jsonDecode(row['content'] as String)),
        createdAt: row['created_at'] as int,
      );
    } on FormatException {
      return null;
    }
  }
}
