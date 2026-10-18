import 'package:sqlite3/common.dart';

import '../domain/text/text_font.dart';
import '../domain/text/user_font.dart';
import 'blob_store.dart';
import 'name_order.dart';
import 'record_fields.dart';
import 'syncable.dart';
import 'syncable_table.dart';

/// Persists the fonts the user imported for text boxes (collection
/// `fonts`, see docs/SYNC_PROTOCOL.md). A font's id is the first half of
/// its file's hash ([TextFont.userIdOf]), so the same file imported on two
/// devices is one record; removing a font tombstones it, and text using it
/// falls back to the default font.
class FontRepository extends SyncableTable {
  FontRepository(super.database, {required super.deviceId, super.clock});

  @override
  String get collection => 'fonts';

  @override
  String get table => 'fonts';

  /// Live fonts by name, in the library's [NameOrder] ("Font 2" before
  /// "Font 10", case-insensitive; UX_AUDIT R26-29).
  List<UserFont> list() =>
      db.select('SELECT * FROM fonts WHERE deleted = 0').map(_rowToFont).toList()
        ..sort(NameOrder.comparator((f) => f.name, (f) => f.id));

  UserFont? get(String id) {
    final rows = db.select('SELECT * FROM fonts WHERE id = ? AND deleted = 0', [id]);
    return rows.isEmpty ? null : _rowToFont(rows.first);
  }

  /// Adds the font file [blob] named [name]; the font already here if it
  /// is (a removed one is brought back).
  UserFont add({required String name, required String blob}) {
    final id = TextFont.userIdOf(blob);
    if (get(id) case final known?) return known;
    final font = UserFont(id: id, name: name, blob: blob, createdAt: clock.nowMs());
    _write(font, updatedAt: nextVersion(id), deviceId: deviceId, dirty: true);
    return font;
  }

  /// Removes font [id]: text using it is shown in the default font.
  void remove(String id) => tombstoneLocal(id);

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
          : {'name': row['name'], 'blob': row['blob'], 'createdAt': row['created_at']},
    );
  }

  @override
  void writeRemote(SyncRecord record) {
    if (record.deleted) {
      db.execute(
        '''
        INSERT INTO fonts (id, name, blob, created_at, updated_at, device_id, deleted, dirty)
        VALUES (?, '', '', 0, ?, ?, 1, 0)
        ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at,
          device_id = excluded.device_id, deleted = 1, dirty = 0''',
        [record.id, record.updatedAt, record.deviceId],
      );
      return;
    }
    _write(parse(record), updatedAt: record.updatedAt, deviceId: record.deviceId, dirty: false);
  }

  /// The font a live `fonts` record holds; throws [FormatException] if it
  /// is malformed (a blob that is no SHA-256, an id that is not its first
  /// half, an empty name).
  static UserFont parse(SyncRecord record) {
    final f = RecordFields(record);
    final blob = f.string('blob');
    if (!BlobStore.isValidId(blob)) f.invalid('blob');
    if (record.id != TextFont.userIdOf(blob)) f.invalid('id');
    final name = f.string('name');
    if (name.trim().isEmpty) f.invalid('name');
    return UserFont(id: record.id, name: name, blob: blob, createdAt: f.integer('createdAt'));
  }

  void _write(
    UserFont font, {
    required int updatedAt,
    required String deviceId,
    required bool dirty,
  }) {
    db.execute(
      '''
      INSERT OR REPLACE INTO fonts (id, name, blob, created_at, updated_at, device_id,
                                    deleted, dirty)
      VALUES (?, ?, ?, ?, ?, ?, 0, ?)''',
      [font.id, font.name, font.blob, font.createdAt, updatedAt, deviceId, dirty ? 1 : 0],
    );
  }

  static UserFont _rowToFont(Row row) => UserFont(
    id: row['id'] as String,
    name: row['name'] as String,
    blob: row['blob'] as String,
    createdAt: row['created_at'] as int,
  );
}
