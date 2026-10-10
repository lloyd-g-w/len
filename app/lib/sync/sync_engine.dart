import 'package:flutter/foundation.dart';

import '../data/app_database.dart';
import '../data/blob_store.dart';
import '../data/notebook_repository.dart';
import '../data/page_repository.dart';
import '../data/settings_repository.dart';
import '../data/stroke_repository.dart';
import '../data/syncable.dart';
import 'blob_sync.dart';
import 'sync_api.dart';

/// What a pull changed locally, so open screens can refresh.
class RemoteChanges {
  RemoteChanges();

  bool notebooks = false;

  /// Notebooks whose page list changed.
  final Set<String> pagesOfNotebooks = {};

  /// Surfaces (pages / canvases) whose strokes changed.
  final Set<String> strokeSurfaces = {};

  bool get isEmpty => !notebooks && pagesOfNotebooks.isEmpty && strokeSurfaces.isEmpty;
}

/// Returns true once a running sync should stop without persisting more
/// (e.g. the server was switched or the app is shutting down).
typedef CancelCheck = bool Function();

/// Runs one push-then-pull sync cycle against the server.
///
/// Push before pull: local edits reach the server first, and anything the
/// server returns that is older is discarded by last-write-wins anyway.
class SyncEngine {
  SyncEngine({
    required this.database,
    required this.settings,
    required this.notebooks,
    required this.pages,
    required this.strokes,
    this.blobs,
  });

  final AppDatabase database;
  final SettingsRepository settings;
  final NotebookRepository notebooks;
  final PageRepository pages;
  final StrokeRepository strokes;

  /// Local blob files; uploaded before any record is pushed.
  final BlobStore? blobs;

  /// Dirty rows read from the database at a time. [SyncApi.push] further
  /// splits them by size.
  static const int _pushPageSize = 500;

  late final Map<String, SyncableStore> _stores = {
    for (final s in [notebooks, pages, strokes]) s.collection: s,
  };

  /// All syncable stores, in push order (parents before children).
  Iterable<SyncableStore> get stores => _stores.values;

  /// Forgets the change-feed position and flags every row for upload, so a
  /// newly configured server receives a complete copy.
  void resetForNewServer() {
    database.transaction(() {
      settings.syncLastSeq = 0;
      for (final store in stores) {
        store.markAllDirty();
      }
      blobs?.markAllNotUploaded();
    });
  }

  /// Pushes local changes, then pulls remote ones. Throws [SyncException]
  /// on network or server errors; [isCancelled] is checked after every
  /// request, before anything is written locally.
  Future<RemoteChanges> sync(SyncApi api, {CancelCheck? isCancelled}) async {
    final cancelled = isCancelled ?? () => false;
    // Blobs first: a record must never reach the server before its blob.
    final blobs = this.blobs;
    if (blobs != null) await BlobSync(blobs).uploadPending(api, cancelled);
    if (cancelled()) return RemoteChanges();
    await _push(api, cancelled);
    return _pull(api, cancelled);
  }

  Future<void> _push(SyncApi api, CancelCheck cancelled) async {
    for (final store in stores) {
      String? after;
      while (!cancelled()) {
        final rows = store.dirtyRecords(_pushPageSize, after: after);
        if (rows.isEmpty) break;
        after = rows.last.id;
        final oversized = await api.push(rows);
        if (cancelled()) return;
        for (final r in oversized) {
          debugPrint('Not syncing oversized ${r.collection}/${r.id}');
        }
        final skipped = {for (final r in oversized) r.id};
        store.markClean([
          for (final r in rows)
            if (!skipped.contains(r.id)) (id: r.id, updatedAt: r.updatedAt),
        ]);
        if (rows.length < _pushPageSize) break;
      }
    }
  }

  Future<RemoteChanges> _pull(SyncApi api, CancelCheck cancelled) async {
    final changes = RemoteChanges();
    var since = settings.syncLastSeq;
    while (!cancelled()) {
      final page = await api.pull(since: since);
      if (cancelled()) break;
      if (page.malformed > 0) {
        debugPrint('Skipped ${page.malformed} malformed records after seq $since');
      }
      database.transaction(() {
        for (final record in page.records) {
          _apply(record, changes);
        }
        settings.syncLastSeq = page.nextSince;
      });
      since = page.nextSince;
      if (!page.hasMore) break;
    }
    return changes;
  }

  void _apply(SyncRecord record, RemoteChanges changes) {
    final store = _stores[record.collection];
    if (store == null) return; // A collection from a newer app version.
    try {
      // Look up the surface before applying: a tombstone may not carry one.
      final previousSurface = store == strokes ? strokes.surfaceOf(record.id) : null;
      if (!store.applyRemote(record)) return;
      switch (store) {
        case NotebookRepository():
          changes.notebooks = true;
        case PageRepository():
          _addKnown(changes.pagesOfNotebooks, pages.notebookOf(record.id));
        case StrokeRepository():
          _addKnown(changes.strokeSurfaces, strokes.surfaceOf(record.id));
          _addKnown(changes.strokeSurfaces, previousSurface);
      }
    } on FormatException catch (e) {
      // Skip malformed records instead of blocking sync forever.
      debugPrint('Skipping malformed ${record.collection}/${record.id}: ${e.message}');
    }
  }

  /// Adds [id] unless it is unknown (null, or empty for placeholder
  /// tombstones of rows never seen locally).
  static void _addKnown(Set<String> ids, String? id) {
    if (id != null && id.isNotEmpty) ids.add(id);
  }
}
