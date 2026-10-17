part of 'sync_engine.dart';

/// Sends records over a live connection: the server's answer, or a
/// [LivePushException].
typedef LivePush = Future<LivePushed> Function(
  List<SyncRecord> records, {
  required int since,
  required bool current,
});

/// How a live push went (see [LiveSyncEngine.pushLive]).
enum LivePushOutcome {
  /// Every row it could push went (none may have been dirty).
  done,

  /// The server has changes this device has not applied yet: apply what
  /// the connection brings, then push again.
  stale,

  /// Rows are left that need a sync run: too many for the connection, a
  /// blob still to upload, a record the server refused, or a failure.
  needsRun,
}

/// Live sync (docs/SYNC_PROTOCOL.md, "Live connection"): records another
/// device's push stored are applied as they arrive, and local edits pushed
/// over the connection, between sync runs (never during one).
extension LiveSyncEngine on SyncEngine {
  /// Records at most per live push; more go through a sync run.
  static const maxLiveRecords = 200;

  /// About the most JSON per live push.
  static const maxLiveBytes = 512 * 1024;

  /// Whether this device may sync live with the server [serverId]: it is
  /// the server it last synced with and holds everything it sent (not a
  /// first sync, which needs every row pushed first).
  bool liveReady(String serverId) =>
      serverId.isNotEmpty && serverId == settings.syncServerId && !settings.syncPushAllFirst;

  /// Applies [message] if it follows on what this device knows
  /// ([knownSeq]): with the pull's rules ([PullApplier], deletion conflicts
  /// included), moving the feed position to its seq. Returns what changed,
  /// or null when changes before it are missing here (pull them).
  Future<RemoteChanges?> applyLive(LiveRecords message, {CancelCheck? isCancelled}) async {
    final changes = RemoteChanges();
    if (message.seq <= knownSeq) return changes; // Pulled already.
    if (message.prevSeq > knownSeq) return null;
    final cancelled = isCancelled ?? () => false;
    final page = PullPage(
      records: message.records,
      nextSince: message.seq,
      hasMore: false,
      lastSeq: message.seq,
      malformed: message.malformed,
    );
    final applied = await _applier.applyPage(
      page,
      changes,
      hadChanges: false,
      budgetUs: SyncEngine.applyBudgetUs,
      pause: () async {
        await Future<void>.delayed(Duration.zero);
        return !cancelled() && !database.isClosed;
      },
    );
    return applied == page.records.length ? changes : null;
  }

  /// Pushes dirty rows over a live connection ([send]): live rows parents
  /// first, then, as `current` pushes (applied only while this device has
  /// every change the server has, so it judged what they race as a pull
  /// would), rows edited in place and tombstones (children first). Rows
  /// referencing a blob not uploaded yet, and more rows than one push
  /// carries, are left to a run.
  Future<LivePushOutcome> pushLive(LivePush send, {CancelCheck? isCancelled}) async {
    final cancelled = isCancelled ?? () => false;
    final pending = blobs?.pendingUploads().toSet() ?? const <String>{};
    var left = false;
    List<SyncRecord> collect(Iterable<SyncableStore> stores, {required bool deleted}) {
      final out = <SyncRecord>[];
      var bytes = 0;
      for (final store in stores) {
        final rows = store.dirtyRecords(maxLiveRecords + 1, deleted: deleted);
        if (rows.length > maxLiveRecords) left = true;
        for (final r in rows.take(maxLiveRecords)) {
          if (out.length >= maxLiveRecords || bytes > maxLiveBytes) {
            left = true;
            return out;
          }
          if (pending.isNotEmpty && BlobReferences.inValue(r.data).any(pending.contains)) {
            left = true; // Its blob goes first, in a run.
            continue;
          }
          out.add(r);
          bytes += _sizeOf(r);
        }
      }
      return out;
    }

    bool inPlace(SyncableStore s) => SyncableTable.editedInPlaceCollections.contains(s.collection);
    final first = collect(stores.where((s) => !inPlace(s)), deleted: false);
    if (!await _pushLive(send, first, current: false, cancelled: cancelled)) {
      return LivePushOutcome.needsRun;
    }
    final second = [
      ...collect(stores.where(inPlace), deleted: false),
      ...collect(stores.toList().reversed, deleted: true),
    ];
    try {
      if (!await _pushLive(send, second, current: true, cancelled: cancelled)) {
        return LivePushOutcome.needsRun;
      }
    } on _Stale {
      return LivePushOutcome.stale;
    }
    return left ? LivePushOutcome.needsRun : LivePushOutcome.done;
  }

  /// Sends [records] (if any) and marks those versions clean; false if it
  /// failed. Throws [_Stale] for a `current` push the server found stale.
  Future<bool> _pushLive(
    LivePush send,
    List<SyncRecord> records, {
    required bool current,
    required CancelCheck cancelled,
  }) async {
    if (records.isEmpty) return true;
    final LivePushed answer;
    try {
      answer = await send(records, since: knownSeq, current: current);
    } on LivePushException catch (e) {
      debugPrint('Live push failed: $e');
      return false;
    }
    if (cancelled() || database.isClosed) return false;
    if (answer.stale) throw const _Stale();
    _stored(answer.applied, answer.serverSeq);
    final byStore = <SyncableStore, List<RowVersion>>{};
    for (final r in records) {
      (byStore[_stores[r.collection]!] ??= []).add((id: r.id, updatedAt: r.updatedAt));
    }
    database.transaction(() {
      byStore.forEach((store, versions) => store.markClean(versions));
    });
    return true;
  }

  /// About the JSON size of [record] (its points dominate strokes).
  static int _sizeOf(SyncRecord record) => record.prepared == null && record.data != null
      ? 256 + (record.data!['points'] as String? ?? '').length
      : 256;
}

/// A `current` live push the server found stale.
class _Stale implements Exception {
  const _Stale();
}

/// A live push that failed: the connection closed, the server refused it
/// or did not answer in time.
class LivePushException implements Exception {
  const LivePushException(this.message, {this.status, this.index});

  final String message;
  final int? status;
  final int? index;

  @override
  String toString() => 'LivePushException($status): $message';
}
