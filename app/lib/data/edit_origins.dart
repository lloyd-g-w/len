import 'package:sqlite3/common.dart';

import 'syncable.dart';

/// A local row's version and what [EditOrigins.of] says of it: whether it
/// has unpushed changes, the [origin] of its content (of the content a
/// tombstone kept, null if unknown) and, on a tombstone, the [base] its
/// deletion knew.
typedef LocalVersion = ({
  RecordVersion version,
  bool deleted,
  bool dirty,
  RecordVersion? origin,
  RecordVersion? base,
});

/// Which edit the content of a row edited in place comes from, and what
/// its deletion knew (docs/SYNC_PROTOCOL.md, "Deletion conflicts"; schema
/// version 15).
///
/// A row's *origin* is the version of the edit whose content it holds: its
/// own version, unless the row is an edit kept over a deletion
/// (`SyncableTable.keepAsEdit`) or a copy a deletion conflict brought back ([revived]),
/// which hold an older edit at a newer version. Stored in `origin_at` /
/// `origin_device`, valid while `origin_for` is the row's `updated_at`, so
/// any local write makes the row an edit of its own. A tombstone's *base*
/// (`base_at` / `base_device`) is the origin of what its deletion replaced:
/// what the deleting device knew. Triggers note both whenever a live row is
/// deleted, and the tombstone keeps the origin of the content it kept.
///
/// On the wire both are a record's `base`: a live record's origin (when it
/// differs from its version), a tombstone's base.
class EditOrigins {
  EditOrigins(this.db, this.table);

  final CommonDatabase db;

  /// The SQL table name (trusted constant).
  final String table;

  /// SQL for a row's origin, its `at` or `device` part ([part]).
  static String _origin(String part) {
    final own = part == 'at' ? 'updated_at' : 'device_id';
    return 'CASE WHEN origin_for = updated_at AND origin_at IS NOT NULL '
        'THEN origin_$part ELSE $own END';
  }

  /// Row [id] as a pull compares it with a record, or null if there is none.
  LocalVersion? of(String id) {
    final rows = db.select(
      'SELECT updated_at, device_id, deleted, dirty, base_at, base_device, '
      'origin_at, origin_device, origin_for FROM $table WHERE id = ?',
      [id],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final version = (updatedAt: row['updated_at'] as int, deviceId: row['device_id'] as String);
    final deleted = row['deleted'] == 1;
    final noted = row['origin_for'] == version.updatedAt
        ? _version(row['origin_at'], row['origin_device'])
        : null;
    return (
      version: version,
      deleted: deleted,
      dirty: row['dirty'] == 1,
      origin: noted ?? (deleted ? null : version),
      base: _version(row['base_at'], row['base_device']),
    );
  }

  /// [record], the push of [row], with the `base` it carries: a tombstone's
  /// base, or a live row's origin unless that is its own version.
  SyncRecord withBase(Row row, SyncRecord record) {
    if (row['deleted'] == 1) return record.withBase(_version(row['base_at'], row['base_device']));
    if (row['origin_for'] != row['updated_at']) return record;
    return record.withBase(_version(row['origin_at'], row['origin_device']));
  }

  /// Notes what pulled [record], just written into row [id], says: a live
  /// record's origin, a tombstone's base. (A tombstone keeps the origin of
  /// the content it kept, see the triggers.)
  void tookRemote(SyncRecord record) {
    final base = record.base;
    if (record.deleted) {
      db.execute('UPDATE $table SET base_at = ?, base_device = ? WHERE id = ?', [
        base?.updatedAt,
        base?.deviceId,
        record.id,
      ]);
    } else {
      db.execute(
        'UPDATE $table SET origin_at = ?, origin_device = ?, origin_for = ? WHERE id = ?',
        [base?.updatedAt, base?.deviceId, base == null ? 0 : record.updatedAt, record.id],
      );
    }
  }

  /// SQL assignments for an `UPDATE` giving a row a new version `?1`
  /// (bound by the caller) that keeps its origin.
  static final keepOrigin =
      'origin_at = ${_origin('at')}, origin_device = ${_origin('device')}, origin_for = ?1';

  /// Marks row [id], brought back at [version], as holding the content its
  /// tombstone kept (whose origin was noted at [tombstone], the tombstone's
  /// version), not an edit of its own. Unknown origins leave it an edit.
  void revived(String id, {required int version, required int tombstone}) => db.execute(
    'UPDATE $table SET origin_for = ? WHERE id = ? AND origin_for = ? AND origin_at IS NOT NULL',
    [version, id, tombstone],
  );

  static RecordVersion? _version(Object? at, Object? device) => switch ((at, device)) {
    (final int at, final String device) => (updatedAt: at, deviceId: device),
    _ => null,
  };
}
