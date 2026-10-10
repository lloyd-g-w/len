import 'package:sqlite3/sqlite3.dart';

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

  Database get db => database.db;

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
    final rows = db.select('SELECT updated_at FROM $table WHERE id = ?', [id]);
    if (rows.isEmpty) return time;
    final previous = rows.first['updated_at'] as int;
    return time > previous ? time : previous + 1;
  }

  @override
  List<SyncRecord> dirtyRecords(int limit, {String? after}) => db
      .select(
        'SELECT * FROM $table WHERE dirty = 1 AND id > ? ORDER BY id LIMIT ?',
        [after ?? '', limit],
      )
      .map(rowToRecord)
      .toList();

  @override
  void markClean(List<RowVersion> versions) {
    if (versions.isEmpty) return;
    final stmt = db.prepare(
      'UPDATE $table SET dirty = 0 WHERE id = ? AND updated_at = ?',
    );
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
    final local = db.select(
      'SELECT updated_at, device_id FROM $table WHERE id = ?',
      [record.id],
    );
    if (local.isNotEmpty &&
        !record.supersedes(
          updatedAt: local.first['updated_at'] as int,
          deviceId: local.first['device_id'] as String,
        )) {
      return false;
    }
    writeRemote(record);
    return true;
  }
}
