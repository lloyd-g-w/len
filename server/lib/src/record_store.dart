/// SQLite-backed last-write-wins record store with a change feed.
library;

import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import 'record.dart';

/// Outcome of [RecordStore.push].
class PushResult {
  const PushResult({required this.applied, required this.ignored, required this.serverSeq});

  /// Number of records that were stored or replaced.
  final int applied;

  /// Number of records discarded by the LWW rule.
  final int ignored;

  /// Current maximum seq after the push.
  final int serverSeq;
}

/// One page of the change feed returned by [RecordStore.pull].
class PullResult {
  const PullResult({required this.records, required this.nextSince, required this.hasMore});

  /// Records with `seq > since`, ordered by seq ascending.
  final List<SyncRecord> records;

  /// Seq of the last returned record, or `since` if none were returned.
  final int nextSince;

  /// Whether more records exist after [nextSince].
  final bool hasMore;
}

/// Thrown when the database was created by a newer, unknown schema version.
class UnsupportedSchemaException implements Exception {
  UnsupportedSchemaException(this.version);

  final int version;

  @override
  String toString() =>
      'UnsupportedSchemaException: database schema version $version is newer '
      'than supported version ${RecordStore.schemaVersion}';
}

/// Stores [SyncRecord]s in a single SQLite table.
///
/// All methods are synchronous, so calls from a single isolate never
/// interleave and each push is applied atomically in one transaction.
class RecordStore {
  RecordStore._(this._db) {
    _configure();
    _migrate();
  }

  /// Opens (creating if needed) the database file at [path].
  factory RecordStore.open(String path) => RecordStore._(sqlite3.open(path));

  /// Opens a fresh in-memory database (for tests).
  factory RecordStore.inMemory() => RecordStore._(sqlite3.openInMemory());

  /// Schema version stored in `PRAGMA user_version`.
  static const schemaVersion = 2;

  final Database _db;

  void _configure() {
    // WAL is silently ignored (stays "memory") for in-memory databases.
    _db.execute('PRAGMA journal_mode = WAL');
    _db.execute('PRAGMA synchronous = NORMAL');
    _db.execute('PRAGMA busy_timeout = 5000');
  }

  void _migrate() {
    final version = _db.userVersion;
    if (version > schemaVersion) throw UnsupportedSchemaException(version);
    if (version < 1) {
      _transaction(() {
        _db.execute('''
          CREATE TABLE records (
            collection TEXT    NOT NULL,
            id         TEXT    NOT NULL,
            updated_at INTEGER NOT NULL,
            device_id  TEXT    NOT NULL,
            deleted    INTEGER NOT NULL,
            data       TEXT,
            seq        INTEGER NOT NULL,
            PRIMARY KEY (collection, id)
          )
        ''');
        // Unique index: enforces seq uniqueness and serves pull queries.
        _db.execute('CREATE UNIQUE INDEX records_seq ON records (seq)');
        _db.userVersion = 1;
      });
    }
    if (version < 2) {
      _transaction(() {
        // Blob garbage collection state (see `BlobGc`): since when each
        // stored blob has been unreferenced, and server-wide facts such as
        // when blobs were last deleted.
        _db.execute('''
          CREATE TABLE blob_gc (
            sha256             TEXT    PRIMARY KEY NOT NULL,
            unreferenced_since INTEGER NOT NULL
          ) WITHOUT ROWID
        ''');
        _db.execute('CREATE TABLE meta (key TEXT PRIMARY KEY NOT NULL, value) WITHOUT ROWID');
        _db.userVersion = 2;
      });
    }
  }

  /// Applies [records] atomically using the LWW rule.
  ///
  /// Every stored or replaced record receives a new seq (max seq + 1).
  PushResult push(List<SyncRecord> records) {
    return _transaction(() {
      var seq = currentSeq();
      var applied = 0;
      final lookup = _db.prepare(
        'SELECT updated_at, device_id FROM records '
        'WHERE collection = ? AND id = ?',
      );
      final upsert = _db.prepare('''
        INSERT INTO records
          (collection, id, updated_at, device_id, deleted, data, seq)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT (collection, id) DO UPDATE SET
          updated_at = excluded.updated_at,
          device_id  = excluded.device_id,
          deleted    = excluded.deleted,
          data       = excluded.data,
          seq        = excluded.seq
      ''');
      try {
        for (final record in records) {
          final stored = lookup.select([record.collection, record.id]);
          final wins =
              stored.isEmpty ||
              record.beats(
                updatedAt: stored.first['updated_at'] as int,
                deviceId: stored.first['device_id'] as String,
              );
          if (!wins) continue;
          seq++;
          applied++;
          upsert.execute([
            record.collection,
            record.id,
            record.updatedAt,
            record.deviceId,
            record.deleted ? 1 : 0,
            record.data == null ? null : jsonEncode(record.data),
            seq,
          ]);
        }
      } finally {
        lookup.close();
        upsert.close();
      }
      return PushResult(applied: applied, ignored: records.length - applied, serverSeq: seq);
    });
  }

  /// Default for [pull]'s `maxDataBytes`.
  static const defaultPullDataBytes = 8 * 1024 * 1024;

  /// Returns up to [limit] records with `seq > since`, ordered by seq.
  ///
  /// The page is also cut short once the stored JSON payloads add up to
  /// [maxDataBytes] (at least one record is always returned), so responses
  /// stay bounded even when records are large; `hasMore` is then true.
  PullResult pull({
    required int since,
    required int limit,
    int maxDataBytes = defaultPullDataBytes,
  }) {
    final stmt = _db.prepare(
      'SELECT collection, id, updated_at, device_id, deleted, data, seq '
      'FROM records WHERE seq > ? ORDER BY seq ASC LIMIT ?',
    );
    final records = <SyncRecord>[];
    var hasMore = false;
    var bytes = 0;
    try {
      // Stream rows so a page never materializes more than it returns.
      final cursor = stmt.selectCursor([since, limit + 1]);
      while (cursor.moveNext()) {
        if (records.length >= limit || (records.isNotEmpty && bytes >= maxDataBytes)) {
          hasMore = true;
          break;
        }
        final row = cursor.current;
        bytes += (row['data'] as String?)?.length ?? 0;
        records.add(_rowToRecord(row));
      }
    } finally {
      stmt.close();
    }
    return PullResult(
      records: records,
      nextSince: records.isEmpty ? since : records.last.seq!,
      hasMore: hasMore,
    );
  }

  /// The current maximum seq, or 0 if the store is empty.
  int currentSeq() {
    final rows = _db.select('SELECT COALESCE(MAX(seq), 0) AS s FROM records');
    return rows.first['s'] as int;
  }

  /// Calls [visit] with the stored JSON `data` of every live (not deleted)
  /// record, streaming rows so memory use stays flat.
  void forEachLiveData(void Function(String data) visit) {
    final stmt = _db.prepare('SELECT data FROM records WHERE deleted = 0 AND data IS NOT NULL');
    try {
      final cursor = stmt.selectCursor();
      while (cursor.moveNext()) {
        visit(cursor.current.columnAt(0) as String);
      }
    } finally {
      stmt.close();
    }
  }

  /// When (ms since epoch) blobs were last deleted by garbage collection;
  /// 0 if never. Reported by `/v1/health` so clients re-check their uploads.
  int get blobsCollectedAt =>
      (_db.select("SELECT value FROM meta WHERE key = 'blobsCollectedAt'").firstOrNull?['value']
          as int?) ??
      0;

  set blobsCollectedAt(int ms) =>
      _db.execute("INSERT OR REPLACE INTO meta (key, value) VALUES ('blobsCollectedAt', ?)", [ms]);

  /// Unreferenced blobs known to garbage collection: sha256 → since when
  /// (ms since epoch) they have been unreferenced.
  Map<String, int> unreferencedBlobs() => {
    for (final row in _db.select('SELECT sha256, unreferenced_since FROM blob_gc'))
      row['sha256'] as String: row['unreferenced_since'] as int,
  };

  /// Replaces the garbage collection marks with [since] (sha256 → ms).
  void setUnreferencedBlobs(Map<String, int> since) => _transaction(() {
    _db.execute('DELETE FROM blob_gc');
    final insert = _db.prepare('INSERT INTO blob_gc (sha256, unreferenced_since) VALUES (?, ?)');
    try {
      for (final e in since.entries) {
        insert.execute([e.key, e.value]);
      }
    } finally {
      insert.close();
    }
  });

  /// Closes the underlying database.
  void close() => _db.close();

  SyncRecord _rowToRecord(Row row) {
    final data = row['data'] as String?;
    return SyncRecord(
      collection: row['collection'] as String,
      id: row['id'] as String,
      updatedAt: row['updated_at'] as int,
      deviceId: row['device_id'] as String,
      deleted: row['deleted'] == 1,
      data: data == null ? null : jsonDecode(data) as Map<String, Object?>,
      seq: row['seq'] as int,
    );
  }

  T _transaction<T>(T Function() body) {
    _db.execute('BEGIN IMMEDIATE');
    try {
      final result = body();
      _db.execute('COMMIT');
      return result;
    } catch (_) {
      // SQLite may already have rolled back (e.g. SQLITE_FULL, or a failed
      // COMMIT); a second ROLLBACK would throw and mask the original error.
      if (!_db.autocommit) _db.execute('ROLLBACK');
      rethrow;
    }
  }
}
