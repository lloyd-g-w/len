import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sqlite3/common.dart' show SqliteException;

import '../data/app_database.dart';
import '../data/deletion_conflicts.dart';
import '../data/edit_origins.dart';
import '../data/element_repository.dart';
import '../data/folder_repository.dart';
import '../data/font_repository.dart';
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
import '../data/versions/version_repository.dart';
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
        VersionRepository() => r.versions.notebookOf(record.id),
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
        case FontRepository():
          changes.fonts = true;
        case NotebookRepository():
          changes.notebooks = true;
          changes.libraryWrites++;
        case PageRepository():
          _addKnown(changes.pagesOfNotebooks, r.pages.notebookOf(record.id));
        // A live stroke or element is now on the surface its record names
        // (written as such); a tombstone stays where it was.
        case StrokeRepository() || ElementRepository():
          for (final surface in {record.data?['surfaceId'] as String?, previousOwner}) {
            if (surface != null && surface.isNotEmpty) changes.addItem(surface, record.id);
          }
        case OutlineRepository():
          _addKnown(changes.outlineOfNotebooks, r.outline.notebookOf(record.id));
          _addKnown(changes.outlineOfNotebooks, previousOwner);
        case RecordingRepository():
          _addKnown(changes.recordingsOfNotebooks, r.recordings.notebookOf(record.id));
          _addKnown(changes.recordingsOfNotebooks, previousOwner);
        case VersionRepository():
          _addKnown(changes.versionsOfNotebooks, r.versions.notebookOf(record.id));
          _addKnown(changes.versionsOfNotebooks, previousOwner);
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

  /// Races of rows edited in place (docs/SYNC_PROTOCOL.md, "Deletion
  /// conflicts"), judged by which edit a version's content comes from (its
  /// origin, [EditOrigins]) rather than by the version alone, where they
  /// differ: an edit kept over a deletion and a copy brought back hold an
  /// older edit at a newer version.
  ///
  /// - Two live versions: the later edit wins, whichever version holds it.
  /// - A deletion and an edit that did not know each other keep the edit,
  ///   whichever is later: a pulled deletion keeps a version here whose
  ///   edit is later than the deletion knew (its base); a deletion here
  ///   takes a pulled edit later than it knew.
  /// - A deletion here that knew the content a pulled version holds stays,
  ///   unless that version brings back the very deletion's rows (a deletion
  ///   conflict elsewhere: the version right after the deletion's); then
  ///   the content this tombstone kept comes back instead if it is later.
  ///
  /// The winner becomes a local edit later than both versions, to push; a
  /// page or notebook deleted with the row comes back once the pull ends
  /// ([DeletionConflicts.resolve]). Without a base (a tombstone whose
  /// knowledge is unknown) only an edit or deletion here that is not pushed
  /// yet counts as unknown to the other side. Returns whether the row
  /// changed, or null when last-write-wins decides as usual.
  ///
  /// Edits and deletions of such rows are pushed after the pull
  /// (`SyncEngine`), so a race is found here rather than decided by
  /// last-write-wins on the server.
  bool? _keepEdit(SyncableStore store, SyncRecord record) {
    final origins = store is SyncableTable ? store.origins : null;
    if (origins == null || store is! SyncableTable) return null;
    final local = origins.of(record.id);
    if (local == null) return null;
    final incoming = (updatedAt: record.updatedAt, deviceId: record.deviceId);
    final holds = record.base ?? incoming; // The edit the pulled content comes from.
    final wins = isLaterVersion(incoming, local.version);
    final kept = local.origin;
    bool keep() {
      store.keepAsEdit(record.id, over: record.updatedAt);
      return true;
    }

    bool take() {
      store.takeRemote(record);
      store.keepAsEdit(record.id, over: local.version.updatedAt);
      return true;
    }

    switch ((local.deleted, record.deleted)) {
      case (false, false):
        // The later edit, whichever version holds it.
        if (wins && isLaterVersion(kept!, holds)) return keep();
        if (!wins && isLaterVersion(holds, kept!)) return take();
      case (false, true) when wins:
        // An edit here the pulled deletion did not know.
        if (_unknown(kept!, to: record.base, unpushed: local.dirty)) return keep();
      case (true, false) when wins:
        if (record.updatedAt == local.version.updatedAt + 1) {
          // This very deletion brought back elsewhere: with the later
          // content, this tombstone's if it kept a later one.
          if (kept != null && isLaterVersion(kept, holds)) {
            store.revive([record.id], version: record.updatedAt + 1);
            // Unless its content was dropped meanwhile.
            if (origins.of(record.id)?.deleted == false) return true;
          }
        } else if (local.base case final knew? when !isLaterVersion(holds, knew)) {
          // Content this deletion knew.
          return keep();
        }
      case (true, false):
        // A pulled edit this deletion did not know.
        if (_unknown(holds, to: local.base, unpushed: local.dirty)) return take();
      case (false, true) || (true, true):
    }
    return null;
  }

  /// Whether a deletion that knew version [to] did not know [version]: it
  /// is later. With [to] unknown, whether the change here is [unpushed].
  static bool _unknown(
    RecordVersion version, {
    required RecordVersion? to,
    required bool unpushed,
  }) => to == null ? unpushed : isLaterVersion(version, to);

  /// Adds [id] unless it is unknown (null, or empty for placeholder
  /// tombstones of rows never seen locally).
  static void _addKnown(Set<String> ids, String? id) {
    if (id != null && id.isNotEmpty) ids.add(id);
  }
}
