import 'package:flutter/foundation.dart';

import '../data/app_database.dart';
import '../data/blob_references.dart';
import '../data/blob_store.dart';
import '../data/element_repository.dart';
import '../data/folder_repository.dart';
import '../data/notebook_repository.dart';
import '../data/outline_repository.dart';
import '../data/page_repository.dart';
import '../data/recording_repository.dart';
import '../data/settings_repository.dart';
import '../data/stroke_repository.dart';
import '../data/syncable.dart';
import '../data/tag_repository.dart';
import '../data/tagging_repository.dart';
import '../data/template_repository.dart';
import 'blob_sync.dart';
import 'sync_api.dart';

/// What a pull changed locally, so open screens can refresh.
class RemoteChanges {
  RemoteChanges();

  bool notebooks = false;

  /// Whether any library folder changed.
  bool folders = false;

  /// Whether any of the user's templates changed.
  bool templates = false;

  /// Whether any tag, or which notebooks and pages carry them, changed.
  bool tags = false;

  /// Notebooks whose page list changed.
  final Set<String> pagesOfNotebooks = {};

  /// Surfaces (pages / canvases) whose content (strokes or elements) changed.
  final Set<String> strokeSurfaces = {};

  /// Notebooks whose own outline changed.
  final Set<String> outlineOfNotebooks = {};

  /// Notebooks whose audio recordings changed.
  final Set<String> recordingsOfNotebooks = {};

  bool get isEmpty =>
      !notebooks &&
      !folders &&
      !templates &&
      !tags &&
      pagesOfNotebooks.isEmpty &&
      strokeSurfaces.isEmpty &&
      recordingsOfNotebooks.isEmpty &&
      outlineOfNotebooks.isEmpty;
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
    required this.folders,
    this.blobs,
    required this.elements,
    required this.recordings,
    required this.templates,
    required this.tags,
    required this.outline,
  });

  final AppDatabase database;
  final SettingsRepository settings;
  final NotebookRepository notebooks;
  final PageRepository pages;
  final StrokeRepository strokes;
  final FolderRepository folders;

  /// Local blob files; uploaded before any record is pushed.
  final BlobStore? blobs;
  final ElementRepository elements;

  /// Audio recordings of notebooks (their audio travels as blobs).
  final RecordingRepository recordings;

  /// The user's own templates (their images travel as blobs).
  final TemplateRepository templates;

  /// Tags; their assignments sync through [TagRepository.taggings].
  final TagRepository tags;

  /// Notebooks' own outlines.
  final OutlineRepository outline;

  /// Which blobs live rows reference.
  late final BlobReferences blobReferences = BlobReferences(database);

  /// What the server reported in the last sync (null before the first sync
  /// that had blobs to consider).
  ServerInfo? serverInfo;

  /// Blobs whose upload failed in the last sync (they are retried).
  int failedBlobUploads = 0;

  /// Why the first of them failed, for the sync status.
  String? blobUploadError;

  /// Consecutive failed upload attempts per blob in this app run.
  final Map<String, int> _uploadFailures = {};

  /// Syncs in a row that a record referencing a blob whose upload keeps
  /// failing is held back. After that it is pushed anyway (other devices
  /// show the blob as missing until it arrives), so a blob that can never be
  /// uploaded cannot keep its records from syncing.
  static const maxHoldBackAttempts = 3;

  /// Dirty rows read from the database at a time. [SyncApi.push] further
  /// splits them by size.
  static const int _pushPageSize = 500;

  late final Map<String, SyncableStore> _stores = {
    for (final s in <SyncableStore>[
      folders,
      templates,
      tags,
      tags.taggings,
      notebooks,
      pages,
      outline,
      strokes,
      elements,
      recordings,
    ])
      s.collection: s,
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
      settings.syncBlobsCollectedAt = 0;
      blobs?.markAllNotUploaded();
    });
    _uploadFailures.clear();
  }

  /// Pushes local changes, then pulls remote ones. Throws [SyncException]
  /// on network or server errors; [isCancelled] is checked after every
  /// request, before anything is written locally.
  Future<RemoteChanges> sync(SyncApi api, {CancelCheck? isCancelled}) async {
    final cancelled = isCancelled ?? () => false;
    failedBlobUploads = 0;
    blobUploadError = null;
    // Blobs first: a record must not reach the server before its blob.
    final blobs = this.blobs;
    final heldBack = blobs == null ? const <String>{} : await _uploadBlobs(api, blobs, cancelled);
    if (cancelled()) return RemoteChanges();
    await _push(api, cancelled, heldBack);
    return _pull(api, cancelled);
  }

  /// Uploads pending blobs and returns those whose records must wait: blobs
  /// still pending (a failed upload, or stored since the upload started),
  /// unless their upload has failed too often.
  Future<Set<String>> _uploadBlobs(SyncApi api, BlobStore blobs, CancelCheck cancelled) async {
    final info = serverInfo = await api.serverInfo();
    if (cancelled()) return const {};
    final collected = info.blobsCollectedAt;
    if (collected != null && collected != settings.syncBlobsCollectedAt) {
      // The server deleted blobs: check that it still has ours.
      database.transaction(() {
        blobs.recheckUploads();
        settings.syncBlobsCollectedAt = collected;
      });
    }
    if (info.maxBlobBytes case final limit?) blobs.retryTooLarge(newLimit: limit);
    final report = await BlobSync(blobs).uploadPending(
      api,
      cancelled,
      referenced: blobReferences.all,
      maxBlobBytes: info.maxBlobBytes,
    );
    _uploadFailures.removeWhere((sha, _) => !report.failed.contains(sha));
    for (final sha in report.failed) {
      _uploadFailures.update(sha, (n) => n + 1, ifAbsent: () => 1);
    }
    failedBlobUploads = report.failed.length;
    blobUploadError = report.error;
    return {
      for (final sha in blobs.pendingUploads())
        if ((_uploadFailures[sha] ?? 0) < maxHoldBackAttempts) sha,
    };
  }

  Future<void> _push(SyncApi api, CancelCheck cancelled, Set<String> heldBackBlobs) async {
    for (final store in stores) {
      String? after;
      while (!cancelled()) {
        final rows = store.dirtyRecords(_pushPageSize, after: after);
        if (rows.isEmpty) break;
        after = rows.last.id;
        final ready = heldBackBlobs.isEmpty
            ? rows
            : [
                for (final r in rows)
                  if (!BlobReferences.inValue(r.data).any(heldBackBlobs.contains)) r,
              ];
        final oversized = ready.isEmpty ? const <SyncRecord>[] : await api.push(ready);
        if (cancelled()) return;
        for (final r in oversized) {
          debugPrint('Not syncing oversized ${r.collection}/${r.id}');
        }
        final skipped = {for (final r in oversized) r.id};
        store.markClean([
          for (final r in ready)
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
      if (!store.applyRemote(record)) return;
      switch (store) {
        case FolderRepository():
          changes.folders = true;
        case TemplateRepository():
          changes.templates = true;
        case TagRepository() || TaggingRepository():
          changes.tags = true;
        case NotebookRepository():
          changes.notebooks = true;
        case PageRepository():
          _addKnown(changes.pagesOfNotebooks, pages.notebookOf(record.id));
        case StrokeRepository():
          _addKnown(changes.strokeSurfaces, strokes.surfaceOf(record.id));
          _addKnown(changes.strokeSurfaces, previousOwner);
        case ElementRepository():
          _addKnown(changes.strokeSurfaces, elements.surfaceOf(record.id));
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
