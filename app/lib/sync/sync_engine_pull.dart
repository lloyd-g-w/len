part of 'sync_engine.dart';

/// Pulling: applies the server's change feed page by page, here in slices
/// between frames, or (a large pull, natively) in a [PullWorker].
extension _SyncPull on SyncEngine {
  Future<RemoteChanges> _pull(SyncApi api, CancelCheck cancelled) async {
    final changes = _unannounced ??= RemoteChanges();
    var since = settings.syncLastSeq;
    var next = api.pullBody(since: since);
    PullWorker? worker;
    var triedWorker = false;
    try {
      while (!cancelled()) {
        final body = await next;
        if (cancelled()) break;
        if (!triedWorker && pullWorker != null && body.length >= SyncEngine.workerFromBytes) {
          triedWorker = true;
          worker = await pullWorker!();
          if (cancelled()) break;
        }
        final page = worker == null
            ? await _applyHere(api, body, since, changes, cancelled, (n) => next = n)
            : await _applyInWorker(worker, api, body, since, changes, cancelled, (n) => next = n);
        if (page.applied < page.total || !page.header.hasMore) break;
        since = page.header.nextSince;
        // The next page is often in already: still let a frame in first.
        if (worker == null) await Future<void>.delayed(Duration.zero);
      }
    } finally {
      await worker?.close();
    }
    return changes;
  }

  /// Fetches the page after [header] ahead, while this one is applied.
  /// Unused when this one is cut short; its failure surfaces only once
  /// awaited.
  void _fetchAhead(SyncApi api, PullHeader header, void Function(Future<Uint8List>) next) {
    if (header.hasMore) next(api.pullBody(since: header.nextSince)..ignore());
  }

  Future<WorkedPage> _applyHere(
    SyncApi api,
    Uint8List body,
    int since,
    RemoteChanges changes,
    CancelCheck cancelled,
    void Function(Future<Uint8List>) next,
  ) async {
    final page = await decodePulled(body, since: since) ?? (throw SyncException.unexpected);
    final header = (nextSince: page.nextSince, hasMore: page.hasMore, malformed: page.malformed);
    if (cancelled()) {
      return WorkedPage(header: header, applied: 0, total: page.records.length, changes: changes);
    }
    _fetchAhead(api, header, next);
    if (page.malformed > 0) {
      debugPrint('Skipped ${page.malformed} malformed records after seq $since');
    }
    // A slice (a few ms) per transaction, with a turn of the event loop
    // between them: applying a whole page at once held the UI thread for a
    // frame or more.
    final applied = await _applier.applyPage(
      page,
      changes,
      hadChanges: false,
      budgetUs: SyncEngine.applyBudgetUs,
      pause: () async {
        await Future<void>.delayed(Duration.zero);
        return !cancelled();
      },
    );
    return WorkedPage(
      header: header,
      applied: applied,
      total: page.records.length,
      changes: changes,
    );
  }

  Future<WorkedPage> _applyInWorker(
    PullWorker worker,
    SyncApi api,
    Uint8List body,
    int since,
    RemoteChanges changes,
    CancelCheck cancelled,
    void Function(Future<Uint8List>) next,
  ) async {
    final WorkedPage? page;
    try {
      page = await worker.apply(
        body,
        since: since,
        hadChanges: !changes.isEmpty,
        onHeader: (header) {
          if (!cancelled()) _fetchAhead(api, header, next);
        },
        cancelled: cancelled,
      );
    } on PullWorkerException catch (e) {
      // Slices it committed before failing are announced with the next
      // sync (pulled again, they change nothing then).
      if (e.changes case final applied? when !applied.isEmpty) {
        changes.addAll(applied);
        database.announceCommit();
      }
      rethrow;
    }
    if (page == null) throw SyncException.unexpected;
    changes.addAll(page.changes);
    // Its commits are not this connection's: tell those watching them.
    if (page.applied > 0) database.announceCommit();
    return page;
  }
}
