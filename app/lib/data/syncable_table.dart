import 'package:sqlite3/common.dart';

import '../core/clock.dart';
import 'app_database.dart';
import 'edit_origins.dart';
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
  /// edit of one can race a deletion of it, so their rows note which edit
  /// their content comes from and their tombstones what the deletion knew
  /// ([EditOrigins]; docs/SYNC_PROTOCOL.md, "Deletion conflicts").
  static const editedInPlaceCollections = {'elements', 'recordings', 'outline'};

  /// Whether this table is one of [editedInPlaceCollections].
  bool get editedInPlace => editedInPlaceCollections.contains(collection);

  /// The origins of this table's rows if it is [editedInPlace].
  late final EditOrigins? origins = editedInPlace ? EditOrigins(db, table) : null;

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
  /// they were. Rows edited in place keep the origin of their content
  /// ([EditOrigins]): a copy brought back is no edit.
  void revive(Iterable<String> ids, {required int version}) {
    final kept = origins == null
        ? ''
        : ', origin_for = CASE WHEN origin_for = updated_at AND origin_at IS NOT NULL '
              'THEN ?1 ELSE 0 END';
    for (final id in ids) {
      db.execute(
        'UPDATE $table SET deleted = 0, dirty = 1, updated_at = ?1, device_id = ?2$kept '
        'WHERE id = ?3 AND deleted = 1 AND updated_at < ?1',
        [version, deviceId, id],
      );
    }
  }

  /// Makes the local version of row [id] a new local edit, later than
  /// version [over] (another device's, or a deletion's here), holding the
  /// same content from the same edit ([EditOrigins]): an edit and a
  /// deletion that did not know each other keep the edit (see
  /// `PullApplier`).
  void keepAsEdit(String id, {required int over}) {
    final now = clock.nowMs();
    final kept = origins == null ? '' : ', ${EditOrigins.keepOrigin}';
    db.execute('UPDATE $table SET updated_at = ?1, device_id = ?2, dirty = 1$kept WHERE id = ?3', [
      now > over ? now : over + 1,
      deviceId,
      id,
    ]);
  }

  /// Writes row [id] with record [data] as a local edit (a version
  /// restored): parsed as a pulled record would be (throws
  /// [FormatException] when malformed, writing nothing).
  void writeLocal(String id, Map<String, Object?> data) {
    writeRemote(
      SyncRecord(
        collection: collection,
        id: id,
        updatedAt: nextVersion(id),
        deviceId: deviceId,
        deleted: false,
        data: data,
      ),
    );
    db.execute('UPDATE $table SET dirty = 1 WHERE id = ?', [id]);
  }

  /// Tombstones live row [id] as a local edit.
  void tombstoneLocal(String id) => db.execute(
    'UPDATE $table SET deleted = 1, dirty = 1, updated_at = ?, device_id = ? '
    'WHERE id = ? AND deleted = 0',
    [nextVersion(id), deviceId, id],
  );

  @override
  List<SyncRecord> dirtyRecords(int limit, {String? after, bool? deleted}) => db
      .select(
        'SELECT * FROM $table WHERE dirty = 1 AND id > ? '
        '${deleted == null ? '' : 'AND deleted = ${deleted ? 1 : 0} '}'
        'ORDER BY id LIMIT ?',
        [after ?? '', limit],
      )
      .map((row) {
        final record = rowToRecord(row);
        return origins?.withBase(row, record) ?? record;
      })
      .toList();

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
    takeRemote(record);
    return true;
  }

  /// Writes remote [record] (see [writeRemote]) with what it says of the
  /// origin of its content or what its deletion knew ([EditOrigins]).
  void takeRemote(SyncRecord record) {
    writeRemote(record);
    origins?.tookRemote(record);
  }
}
