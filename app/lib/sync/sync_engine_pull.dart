part of 'sync_engine.dart';

/// Pulling: applies the server's change feed page by page.
extension _SyncPull on SyncEngine {
  Future<RemoteChanges> _pull(SyncApi api, CancelCheck cancelled) async {
    final changes = _unannounced ??= RemoteChanges();
    var next = api.pull(since: settings.syncLastSeq);
    while (!cancelled()) {
      final since = settings.syncLastSeq;
      final page = await next;
      if (cancelled()) break;
      // Fetch (and decode) the next page while this one is applied. Unused
      // when this one is cut short; its failure surfaces only once awaited.
      if (page.hasMore) next = api.pull(since: page.nextSince)..ignore();
      if (page.malformed > 0) {
        debugPrint('Skipped ${page.malformed} malformed records after seq $since');
      }
      final revival = Revival();
      final records = page.records;
      var applied = 0;
      while (true) {
        // A slice (a few ms) per transaction, with a turn of the event loop between
        // them: applying a whole page at once held the UI thread for a
        // frame or more. Only the last slice moves the feed position, so a
        // page cut short is pulled again (applying a record twice is a
        // no-op under last-write-wins).
        final slice = Stopwatch()..start();
        database.transaction(() {
          while (applied < records.length && slice.elapsedMicroseconds < SyncEngine.applyBudgetUs) {
            _apply(records[applied++], changes, revival);
          }
          if (applied < records.length) return;
          // Once everything is in: deletions that raced edits come back.
          if (!page.hasMore && !changes.isEmpty) _conflicts.resolve(revival);
          settings.syncLastSeq = page.nextSince;
        });
        if (applied == records.length) break;
        await Future<void>.delayed(Duration.zero);
        if (cancelled()) break;
      }
      changes.addRevival(revival);
      if (applied < records.length || !page.hasMore) break;
      // The next page is often in already: still let a frame in first.
      await Future<void>.delayed(Duration.zero);
    }
    return changes;
  }

  void _apply(SyncRecord record, RemoteChanges changes, Revival revival) {
    final store = _stores[record.collection];
    if (store == null) return; // A collection this app does not know.
    try {
      // Look up the owner (surface or notebook) before applying: a tombstone
      // may not carry one.
      final previousOwner = switch (store) {
        StrokeRepository() => strokes.surfaceOf(record.id),
        ElementRepository() => elements.surfaceOf(record.id),
        RecordingRepository() => recordings.notebookOf(record.id),
        OutlineRepository() => outline.notebookOf(record.id),
        _ => null,
      };
      // A deleted notebook or page edited elsewhere: see DeletionConflicts.
      final deletion = record.deleted ? null : _conflicts.tombstoneOf(record.collection, record.id);
      if (!store.applyRemote(record)) return;
      if (deletion != null) {
        _conflicts.reviveDeleted(record.collection, record.id, deletion, revival);
      }
      switch (store) {
        case FolderRepository():
          changes.folders = true;
        case TemplateRepository():
          changes.templates = true;
        case NotebookRepository():
          changes.notebooks = true;
        case PageRepository():
          _addKnown(changes.pagesOfNotebooks, pages.notebookOf(record.id));
        // A live stroke or element is now on the surface its record names
        // (written as such); a tombstone stays where it was.
        case StrokeRepository() || ElementRepository():
          _addKnown(changes.strokeSurfaces, record.data?['surfaceId'] as String?);
          _addKnown(changes.strokeSurfaces, previousOwner);
        case OutlineRepository():
          _addKnown(changes.outlineOfNotebooks, outline.notebookOf(record.id));
          _addKnown(changes.outlineOfNotebooks, previousOwner);
        case RecordingRepository():
          _addKnown(changes.recordingsOfNotebooks, recordings.notebookOf(record.id));
          _addKnown(changes.recordingsOfNotebooks, previousOwner);
      }
    } on FormatException catch (e) {
      // Skip malformed records instead of blocking sync forever.
      debugPrint('Skipping malformed ${record.collection}/${record.id}: ${e.message}');
    } on Error catch (e) {
      // A value parsing missed (a cast, a range): still one bad record,
      // which must not stop every later one from syncing. (Database errors
      // are exceptions and still abort the pull.)
      if (e is! TypeError && e is! ArgumentError) rethrow;
      debugPrint('Skipping unreadable ${record.collection}/${record.id}: $e');
    }
  }

  /// Adds [id] unless it is unknown (null, or empty for placeholder
  /// tombstones of rows never seen locally).
  static void _addKnown(Set<String> ids, String? id) {
    if (id != null && id.isNotEmpty) ids.add(id);
  }
}
