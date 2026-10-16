import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sqlite3/common.dart' show SqliteException;

import '../data/app_database.dart';
import '../data/deletion_conflicts.dart';
import '../data/element_repository.dart';
import '../data/folder_repository.dart';
import '../data/notebook_repository.dart';
import '../data/outline_repository.dart';
import '../data/page_repository.dart';
import '../data/recording_repository.dart';
import '../data/repositories.dart';
import '../data/settings_repository.dart';
import '../data/stroke_repository.dart';
import '../data/syncable.dart';
import '../data/syncable_table.dart';
import '../data/template_repository.dart';
import 'pull_page.dart';
import 'remote_changes.dart';

/// Writes pulled pages into the database, a slice (a transaction) at a
/// time: on the UI isolate in turns between frames, or in a worker isolate
/// over its own connection (`PullWorker`). Either way the same code runs.
class PullApplier {
  PullApplier({
    required this.database,
    required this.settings,
    required this.repositories,
    required this.stores,
  }) : _conflicts = DeletionConflicts(repositories.notebooks);

  final AppDatabase database;
  final SettingsRepository settings;
  final Repositories repositories;

  /// The stores by collection.
  final Map<String, SyncableStore> stores;

  /// Brings back deletions that raced edits elsewhere.
  final DeletionConflicts _conflicts;

  /// Applies [page] into [changes], a slice of [budgetUs] µs per
  /// transaction (ended early once [yieldNow] says so), calling [pause]
  /// between slices (false: stop there).
  /// Returns how many records were applied; only once all are does the
  /// feed position move (in the last slice's transaction), so a page cut
  /// short is pulled again (applying a record twice is a no-op under
  /// last-write-wins). On the last page ([PullPage.hasMore] false), if
  /// anything changed in this pull ([hadChanges], or this page), deletions
  /// that raced edits come back in that transaction too.
  Future<int> applyPage(
    PullPage page,
    RemoteChanges changes, {
    required bool hadChanges,
    required int budgetUs,
    required Future<bool> Function() pause,
    bool Function()? yieldNow,
  }) async {
    final records = page.records;
    var applied = 0;
    var busy = 0;
    while (true) {
      final slice = Stopwatch()..start();
      final start = applied;
      // What this slice brought back counts once it is committed: a slice
      // rolled back (and tried again) or failing revived nothing, while
      // those before it did whatever comes after.
      final revival = Revival();
      try {
        database.transaction(() {
          while (applied < records.length && slice.elapsedMicroseconds < budgetUs) {
            _apply(records[applied++], changes, revival);
            if (yieldNow?.call() ?? false) break;
            if (applied - start == debugSliceRecords) break;
          }
          if (applied < records.length) return;
          if (!page.hasMore && (hadChanges || !changes.isEmpty)) _conflicts.resolve(revival);
          settings.syncLastSeq = page.nextSince;
        });
        changes.addRevival(revival);
        busy = 0;
      } on SqliteException catch (e) {
        // Another connection's transaction outlasted the busy wait (a
        // worker's, waiting for a long one of the app's): try again.
        if (e.resultCode != _sqliteBusy || ++busy > maxBusyRetries) rethrow;
        applied = start;
        if (!await pause()) break;
        continue;
      }
      if (applied == records.length || !await pause()) break;
    }
    return applied;
  }

  /// At most this many records per slice, if set: tests cut slices where
  /// they need them, whatever the machine's speed (a worker isolate takes
  /// it over when it starts).
  static int? debugSliceRecords;

  /// How many slices in a row may find the database locked (each after
  /// waiting [AppDatabase.busyTimeoutMs]) before the pull fails.
  static const maxBusyRetries = 6;

  static const _sqliteBusy = 5;

  void _apply(SyncRecord record, RemoteChanges changes, Revival revival) {
    final store = stores[record.collection];
    if (store == null) return; // A collection this app does not know.
    final r = repositories;
    try {
      // Look up the owner (surface or notebook) before applying: a tombstone
      // may not carry one.
      final previousOwner = switch (store) {
        StrokeRepository() => r.strokes.surfaceOf(record.id),
        ElementRepository() => r.elements.surfaceOf(record.id),
        RecordingRepository() => r.recordings.notebookOf(record.id),
        OutlineRepository() => r.outline.notebookOf(record.id),
        _ => null,
      };
      // A deleted notebook or page edited elsewhere: see DeletionConflicts.
      final deletion = record.deleted ? null : _conflicts.tombstoneOf(record.collection, record.id);
      if (!(_keepEdit(store, record) ?? store.applyRemote(record))) return;
      if (deletion != null) {
        _conflicts.reviveDeleted(record.collection, record.id, deletion, revival);
      }
      switch (store) {
        case FolderRepository():
          changes.folders = true;
          changes.libraryWrites++;
        case TemplateRepository():
          changes.templates = true;
        case NotebookRepository():
          changes.notebooks = true;
          changes.libraryWrites++;
        case PageRepository():
          _addKnown(changes.pagesOfNotebooks, r.pages.notebookOf(record.id));
        // A live stroke or element is now on the surface its record names
        // (written as such); a tombstone stays where it was.
        case StrokeRepository() || ElementRepository():
          _addKnown(changes.strokeSurfaces, record.data?['surfaceId'] as String?);
          _addKnown(changes.strokeSurfaces, previousOwner);
        case OutlineRepository():
          _addKnown(changes.outlineOfNotebooks, r.outline.notebookOf(record.id));
          _addKnown(changes.outlineOfNotebooks, previousOwner);
        case RecordingRepository():
          _addKnown(changes.recordingsOfNotebooks, r.recordings.notebookOf(record.id));
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

  /// Collections whose rows are edited in place (strokes are replaced
  /// instead, and the library's rows are organisation, not content).
  static const editedInPlace = {'elements', 'recordings', 'outline'};

  /// An edit and a deletion of the same row that did not know each other
  /// keep the edit, whichever is later (docs/SYNC_PROTOCOL.md, "Deletion
  /// conflicts"): a deletion arriving for a row with an edit here that was
  /// never pushed, or an edit arriving for a row deleted here, unpushed,
  /// when the deletion would win. The edit then becomes a local edit later
  /// than both, to push; a page or notebook deleted with the row comes back
  /// once the pull ends ([DeletionConflicts.resolve]). Returns whether the
  /// row changed, or null when [record] is no such race.
  ///
  /// Such rows are pushed after the pull (`SyncEngine`), so they are still
  /// dirty here. (Not on a first sync or after switching servers: every
  /// row is pushed before the pull then.)
  bool? _keepEdit(SyncableStore store, SyncRecord record) {
    if (store is! SyncableTable || !editedInPlace.contains(record.collection)) return null;
    final rows = database.select(
      'SELECT updated_at, device_id, deleted FROM ${store.table} WHERE id = ? AND dirty = 1',
      [record.id],
    );
    if (rows.isEmpty || (rows.first['deleted'] == 1) == record.deleted) return null;
    final local = rows.first['updated_at'] as int;
    final wins = record.supersedes(updatedAt: local, deviceId: rows.first['device_id'] as String);
    if (record.deleted) {
      // An edit here the deleting device cannot have seen.
      if (!wins) return null;
      store.keepAsEdit(record.id, over: record.updatedAt);
    } else {
      // An edit elsewhere this unpushed deletion did not know.
      if (wins) return null;
      store.writeRemote(record);
      store.keepAsEdit(record.id, over: local);
    }
    return true;
  }

  /// Adds [id] unless it is unknown (null, or empty for placeholder
  /// tombstones of rows never seen locally).
  static void _addKnown(Set<String> ids, String? id) {
    if (id != null && id.isNotEmpty) ids.add(id);
  }
}
