part of 'blob_store.dart';

/// [BlobStore]'s cleanup: garbage collection, freeing local copies of
/// uploaded blobs and discarding blobs a cancelled import stored.
mixin _BlobCleanup {
  AppDatabase get database;
  BlobBackend get backend;
  Clock get clock;
  FreedBlobs get freed;

  Future<T> _exclusive<T>(Future<T> Function() action);
  bool _isRecorded(String sha);
  void _setUnreferencedSince(String sha, int? ms);

  /// Deletes blobs that [referenced] (the ids live rows reference) has not
  /// contained for [grace], counted from the first run that found them
  /// unreferenced, and returns their ids. Upload state does not matter: an
  /// unreferenced blob is never uploaded. Runs exclusively with the `put`
  /// methods, and storing a blob again restarts its grace period, so a blob
  /// being (re)imported is never deleted underneath its new reference.
  ///
  /// Each blob's row goes in a transaction of its own that first asks
  /// [stillReferenced] (cheap: one blob) again, as a pull (in a worker, or
  /// between slices) may have committed a record referencing it while
  /// earlier blobs were deleted; its file goes after. A record committed
  /// later finds the blob missing and fetches it again.
  Future<List<String>> collectGarbage(
    Set<String> Function() referenced, {
    required bool Function(String sha) stillReferenced,
    Duration grace = BlobStore.gcGrace,
  }) => _exclusive(() async {
    final now = clock.nowMs();
    final live = referenced();
    final due = <String>[];
    database.transaction(() {
      freed.keepOnly(live);
      for (final row in database.db.select('SELECT sha256, unreferenced_since FROM blobs')) {
        final sha = row['sha256'] as String;
        final since = row['unreferenced_since'] as int?;
        if (live.contains(sha)) {
          if (since != null) _setUnreferencedSince(sha, null);
        } else if (since == null) {
          _setUnreferencedSince(sha, now);
        } else if (now - since >= grace.inMilliseconds) {
          due.add(sha);
        }
      }
    });
    final deleted = <String>[];
    for (final sha in due) {
      final row = database.transaction(() {
        if (stillReferenced(sha)) {
          _setUnreferencedSince(sha, null);
          return null;
        }
        final row = database.db.select('SELECT * FROM blobs WHERE sha256 = ?', [sha]).first;
        database.db.execute('DELETE FROM blobs WHERE sha256 = ?', [sha]);
        return row;
      });
      if (row == null) continue;
      try {
        await backend.delete(sha);
      } on Object catch (e) {
        // Recorded again as it was (a later run retries), never left as
        // a file no row knows; the other blobs still go.
        debugPrint('Blob $sha was not deleted: $e');
        _restoreRow(row);
        continue;
      }
      deleted.add(sha);
    }
    return deleted;
  });

  /// Removes this device's copies of [shas], files the sync server holds
  /// (they download again when shown; Settings → Storage, "Free up"), and
  /// returns how many went and their bytes. Each goes only if it still counts as
  /// uploaded (not refused as too large) and [stillRemovable] confirms it
  /// right then, exclusively with the `put` methods: its row first (it then
  /// counts as missing, so a reader fetches it again, after this), then its
  /// file; a file that can't be deleted (in use) is recorded again as it was.
  Future<({int count, int bytes})> removeLocalCopies(
    Iterable<String> shas, {
    required bool Function(String sha) stillRemovable,
  }) => _exclusive(() async {
    var count = 0, bytes = 0;
    for (final sha in shas) {
      final row = database.transaction(() {
        final row = database.db.select(
          'SELECT * FROM blobs WHERE sha256 = ? AND uploaded = 1 AND rejected_limit IS NULL',
          [sha],
        ).firstOrNull;
        if (row == null || !stillRemovable(sha)) return null;
        database.db.execute('DELETE FROM blobs WHERE sha256 = ?', [sha]);
        freed.add(sha, row['mime'] as String, clock.nowMs());
        return row;
      });
      if (row == null) continue;
      try {
        await backend.delete(sha);
      } on Object catch (e) {
        debugPrint('Blob $sha was not removed: $e');
        database.transaction(() {
          _restoreRow(row);
          freed.remove(sha);
        });
        continue;
      }
      count++;
      bytes += row['size'] as int;
    }
    return (count: count, bytes: bytes);
  });

  /// Deletes blob [sha] right away unless [referenced] (the ids live rows
  /// reference) contains it, e.g. after a cancelled import stored it.
  Future<void> discardIfUnreferenced(String sha, Set<String> Function() referenced) =>
      _exclusive(() async {
        if (referenced().contains(sha) || !_isRecorded(sha)) return;
        await backend.delete(sha);
        database.db.execute('DELETE FROM blobs WHERE sha256 = ?', [sha]);
      });

  /// Records a blob's [row] again as it was (its file could not be deleted).
  void _restoreRow(Row row) => database.db.execute(
    'INSERT OR IGNORE INTO blobs (${row.keys.join(', ')}) '
    'VALUES (${List.filled(row.length, '?').join(', ')})',
    row.values,
  );
}
