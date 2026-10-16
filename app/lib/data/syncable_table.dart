import 'package:sqlite3/common.dart';

import '../core/clock.dart';
import 'app_database.dart';
import 'syncable.dart';

/// Shared sync bookkeeping for tables with the standard
/// `updated_at / device_id / deleted / dirty` columns.
abstract class SyncableTable implements SyncableStore {
  SyncableTable(this.database, {required this.deviceId, this.clock = const Clock()});

  final AppDatabase database;

  /// This installation's device id; stamped on every local write.
  final String deviceId;

  /// Source of local write timestamps and new ids.
  final Clock clock;

  /// The SQL table name (trusted constant, never user input).
  String get table;

  /// Collections whose rows are edited in place (strokes are replaced
  /// instead, and the library's rows are organisation, not content): an
  /// edit of one can race a deletion of it, so their tombstones note what
  /// the deletion knew and their revived rows are marked as such (columns
  /// `base_at`, `base_device`, `revived_at`; docs/SYNC_PROTOCOL.md,
  /// "Deletion conflicts").
  static const editedInPlaceCollections = {'elements', 'recordings', 'outline'};

  /// Whether this table is one of [editedInPlaceCollections].
  bool get editedInPlace => editedInPlaceCollections.contains(collection);

  CommonDatabase get db => database.db;

  /// Converts a row into its wire record.
  SyncRecord rowToRecord(Row row);

  /// Writes a winning remote record into the table (insert or replace).
  ///
  /// [SyncRecord.data] is non-null for live records. Must throw
  /// [FormatException] for invalid payloads before writing anything.
  void writeRemote(SyncRecord record);

  /// The `updated_at` to stamp on a local write of row [id]: the current
  /// time, but always later than the row's current version.
  ///
  /// Wall clocks differ between devices (and can jump backwards); without
  /// this, an edit made here could lose under last-write-wins to the very
  /// version it replaces, or reuse the version of an in-flight push so that
  /// `markClean` wrongly clears it.
  int nextVersion(String id, [int? now]) {
    final time = now ?? clock.nowMs();
    final rows = database.select('SELECT updated_at FROM $table WHERE id = ?', [id]);
    if (rows.isEmpty) return time;
    final previous = rows.first['updated_at'] as int;
    return time > previous ? time : previous + 1;
  }

  /// The newest version among rows matching the SQL condition [where]
  /// (0 if none): a batch of writes stamped later than it beats them all.
  int latestVersion(String where, List<Object?> args) =>
      db.select('SELECT MAX(updated_at) AS v FROM $table WHERE $where', args).first['v'] as int? ??
      0;

  /// Tombstones every live row on the surfaces [surfaceIds] (a table with
  /// `surface_id` and a chunk index [chunkTable]), stamped like
  /// [nextVersion] would stamp each, or all with [version]. One statement
  /// per surface rather than per row: a deleted notebook may hold hundreds
  /// of thousands of strokes. Tombstones keep their payload (see
  /// `DeletionConflicts`).
  void tombstoneSurfaces(Iterable<String> surfaceIds, {required String chunkTable, int? version}) {
    final now = clock.nowMs();
    database.transaction(() {
      for (final surfaceId in surfaceIds) {
        db.execute(
          'UPDATE $table SET deleted = 1, dirty = 1, device_id = ?, '
          'updated_at = ${version == null ? 'MAX(?, updated_at + 1)' : '?'} '
          'WHERE surface_id = ? AND deleted = 0',
          [deviceId, version ?? now, surfaceId],
        );
        // Only live rows are in the chunk index.
        db.execute('DELETE FROM $chunkTable WHERE surface_id = ?', [surfaceId]);
      }
    });
  }

  /// Brings tombstoned rows [ids] back as local edits at [version] (a
  /// deletion that raced an edit, see `DeletionConflicts`: the version right
  /// after the deletion's, so a copy brought back never beats an edit made
  /// elsewhere). Tables whose tombstones keep every column revive them as
  /// they were. Rows edited in place are marked as revived at [version] (see
  /// [editedInPlace]), keeping the base of the deletion they undo.
  void revive(Iterable<String> ids, {required int version}) {
    final marked = editedInPlace ? ', revived_at = ?1' : '';
    for (final id in ids) {
      db.execute(
        'UPDATE $table SET deleted = 0, dirty = 1, updated_at = ?1, device_id = ?2$marked '
        'WHERE id = ?3 AND deleted = 1 AND updated_at < ?1',
        [version, deviceId, id],
      );
    }
  }

  /// What a pull needs to know of local row [id] of a table edited in place
  /// ([editedInPlace]) to tell an edit and a deletion that did not know
  /// each other; null if there is no such row.
  LocalVersion? localVersion(String id) {
    final rows = database.select(
      'SELECT updated_at, device_id, deleted, dirty, base_at, base_device, revived_at '
      'FROM $table WHERE id = ?',
      [id],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final at = row['updated_at'] as int;
    return (
      version: (updatedAt: at, deviceId: row['device_id'] as String),
      deleted: row['deleted'] == 1,
      dirty: row['dirty'] == 1,
      base: _baseOf(row),
      revived: row['deleted'] == 0 && row['revived_at'] == at,
    );
  }

  static RecordVersion? _baseOf(Row row) => switch ((row['base_at'], row['base_device'])) {
    (final int at, final String device) => (updatedAt: at, deviceId: device),
    _ => null,
  };

  /// Makes the local version of row [id] a new local edit, later than
  /// version [over] (another device's, or a deletion's here): an edit and
  /// a deletion that did not know each other keep the edit (see
  /// `PullApplier`).
  void keepAsEdit(String id, {required int over}) {
    final now = clock.nowMs();
    db.execute('UPDATE $table SET updated_at = ?, device_id = ?, dirty = 1 WHERE id = ?', [
      now > over ? now : over + 1,
      deviceId,
      id,
    ]);
  }

  @override
  List<SyncRecord> dirtyRecords(int limit, {String? after, bool? deleted}) => db
      .select(
        'SELECT * FROM $table WHERE dirty = 1 AND id > ? '
        '${deleted == null ? '' : 'AND deleted = ${deleted ? 1 : 0} '}'
        'ORDER BY id LIMIT ?',
        [after ?? '', limit],
      )
      .map(editedInPlace ? _recordWithBase : rowToRecord)
      .toList();

  /// [rowToRecord] with the base a tombstone or a revived row carries.
  SyncRecord _recordWithBase(Row row) {
    final record = rowToRecord(row);
    final carries = row['deleted'] == 1 || row['revived_at'] == row['updated_at'];
    return carries ? record.withBase(_baseOf(row)) : record;
  }

  @override
  void markClean(List<RowVersion> versions) {
    if (versions.isEmpty) return;
    final stmt = db.prepare('UPDATE $table SET dirty = 0 WHERE id = ? AND updated_at = ?');
    try {
      database.transaction(() {
        for (final v in versions) {
          stmt.execute([v.id, v.updatedAt]);
        }
      });
    } finally {
      stmt.close();
    }
  }

  @override
  void markAllDirty() => db.execute('UPDATE $table SET dirty = 1');

  @override
  bool applyRemote(SyncRecord record) {
    if (!record.deleted && record.data == null) {
      throw FormatException('Live ${record.collection}/${record.id} has no data');
    }
    final local = database.select('SELECT updated_at, device_id FROM $table WHERE id = ?', [
      record.id,
    ]);
    if (local.isNotEmpty &&
        !record.supersedes(
          updatedAt: local.first['updated_at'] as int,
          deviceId: local.first['device_id'] as String,
        )) {
      return false;
    }
    writeRemote(record);
    if (editedInPlace) {
      // What the deletion knew, or what the one a revived copy undoes knew.
      db.execute('UPDATE $table SET base_at = ?, base_device = ?, revived_at = ? WHERE id = ?', [
        record.base?.updatedAt,
        record.base?.deviceId,
        record.base != null && !record.deleted ? record.updatedAt : 0,
        record.id,
      ]);
    }
    return true;
  }
}

/// A local row's version and what [SyncableTable.localVersion] says of it:
/// whether it has unpushed changes, the [base] its tombstone or revived
/// copy carries, and whether it is a copy a deletion conflict brought back
/// ([revived]) and not edited since.
typedef LocalVersion = ({
  RecordVersion version,
  bool deleted,
  bool dirty,
  RecordVersion? base,
  bool revived,
});
