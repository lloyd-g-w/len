import 'package:flutter/foundation.dart';

import '../data/app_database.dart';
import '../data/blob_references.dart';
import '../data/blob_store.dart';
import '../data/repositories.dart';
import '../data/settings_repository.dart';
import '../data/syncable.dart';
import '../platform/pull_decoder.dart';
import 'blob_sync.dart';
import 'pull_applier.dart';
import 'pull_worker.dart';
import 'remote_changes.dart';
import 'sync_api.dart';

export 'remote_changes.dart';

part 'sync_engine_pull.dart';

/// Returns true once a running sync should stop without persisting more
/// (e.g. the server was switched or the app is shutting down).
typedef CancelCheck = bool Function();

/// How far a pull is (see [SyncEngine.onPullProgress]).
typedef PullProgress = ({int from, int done, int total, RemoteChanges changes});

/// Runs one push-then-pull sync cycle against the server.
///
/// Push before pull: local edits reach the server first, and anything the
/// server returns that is older is discarded by last-write-wins anyway.
class SyncEngine {
  SyncEngine({
    required this.database,
    required this.settings,
    required this.repositories,
    this.blobs,
    this.pullWorker,
  });

  final AppDatabase database;
  final SettingsRepository settings;

  /// The synced repositories.
  final Repositories repositories;

  /// Local blob files; uploaded before any record is pushed.
  final BlobStore? blobs;

  /// Starts a worker that applies pulled pages off the UI isolate, over
  /// its own connection (native, file databases); null, or a worker that
  /// fails to start: pages are applied here in slices between frames.
  final PullWorkerStart? pullWorker;

  /// Pulled pages from this size (bytes) on start a [pullWorker] for the
  /// rest of the pull: a first sync or a big catch-up. Smaller pulls (an
  /// incremental sync's few records) are applied in place.
  @visibleForTesting
  static int workerFromBytes = 64 * 1024;

  /// Writes pulled pages (on this isolate).
  late final PullApplier _applier = PullApplier(
    database: database,
    settings: settings,
    repositories: repositories,
    stores: _stores,
  );

  /// Which blobs live rows reference.
  late final BlobReferences blobReferences = BlobReferences(database);

  /// What the server reported in the last sync (null before the first).
  ServerInfo? serverInfo;

  /// Called after each page of a pull that has more to come: the feed
  /// entries pulled ([PullProgress.done]) of those there were when the
  /// pull began ([PullProgress.total], growing if the server does), the
  /// feed position it began at ([PullProgress.from]: 0 for a first sync)
  /// and what the pull changed so far.
  void Function(PullProgress progress)? onPullProgress;

  /// Blobs whose upload failed in the last sync (they are retried).
  int failedBlobUploads = 0;

  /// Why the first of them failed, for the sync status.
  String? blobUploadError;

  /// Why this device last synced everything again from scratch, until the
  /// controller has told the user ([takeResync]); null if it has not.
  String? _resync;

  /// Says (once) why everything was synced again: the server changed or
  /// lost history. Null if nothing happened since the last call.
  String? takeResync() {
    final reason = _resync;
    _resync = null;
    return reason;
  }

  /// What pulls applied in syncs that failed afterwards (a dropped
  /// connection on a later page): carried into the next sync's result, so
  /// open screens still refresh and deletion conflicts are still resolved.
  RemoteChanges? _unannounced;

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

  Map<String, SyncableStore> get _stores => repositories.byCollection;

  /// All syncable stores, in push order (parents before children).
  Iterable<SyncableStore> get stores => _stores.values;

  /// Forgets the change-feed position and flags every row for upload, so a
  /// new server (or one that lost changes) receives a complete copy.
  void resetForNewServer({String serverId = ''}) {
    database.transaction(() {
      settings.syncLastSeq = 0;
      for (final store in stores) {
        store.markAllDirty();
      }
      settings
        ..syncBlobsCollectedAt = 0
        ..syncServerId = serverId;
      blobs?.markAllNotUploaded();
    });
    _uploadFailures.clear();
  }

  /// Pushes local changes, then pulls remote ones. Throws [SyncException]
  /// on network or server errors; [isCancelled] is checked after every
  /// request, before anything is written locally.
  ///
  /// Every cycle first reads the server's id: under a new one (another
  /// server, or one restored from a backup) everything is uploaded again
  /// and pulled from the start. A server that turns out to have lost
  /// changes this device saw answers [SyncFailure.historyLost] and takes a
  /// new id, so the cycle starts over once.
  Future<RemoteChanges> sync(SyncApi api, {CancelCheck? isCancelled}) async {
    final cancelled = isCancelled ?? () => false;
    for (var attempt = 0; ; attempt++) {
      try {
        final changes = await _cycle(api, cancelled);
        // A cancelled run's changes are not announced (see SyncController).
        if (!cancelled()) _unannounced = null;
        return changes;
      } on SyncException catch (e) {
        if (e.kind != SyncFailure.historyLost || attempt > 0 || cancelled()) rethrow;
        debugPrint('The sync server lost changes; uploading everything again');
        resetForNewServer();
        _resync = 'The sync server lost recent changes, so everything was synced again';
      }
    }
  }

  Future<RemoteChanges> _cycle(SyncApi api, CancelCheck cancelled) async {
    failedBlobUploads = 0;
    blobUploadError = null;
    final info = serverInfo = await api.serverInfo();
    if (cancelled()) return RemoteChanges();
    if (info.serverId != settings.syncServerId) {
      // Not on the first sync with a server: nothing to explain then.
      if (settings.syncServerId.isNotEmpty) {
        debugPrint('Another sync server (or a restored one); syncing everything again');
        _resync ??= 'The sync server changed, so everything was synced again';
      }
      resetForNewServer(serverId: info.serverId);
    }
    // Blobs first: a record must not reach the server before its blob.
    final blobs = this.blobs;
    if (blobs != null) await _uploadBlobs(api, blobs, info, cancelled);
    if (cancelled()) return RemoteChanges();
    await _push(api, cancelled);
    final changes = await _pull(api, cancelled);
    // Content brought back by a deletion conflict goes out right away.
    if (changes.revived && !cancelled()) await _push(api, cancelled);
    return changes;
  }

  /// Uploads pending blobs, counting failures per blob.
  Future<void> _uploadBlobs(
    SyncApi api,
    BlobStore blobs,
    ServerInfo info,
    CancelCheck cancelled,
  ) async {
    if (info.blobsCollectedAt != settings.syncBlobsCollectedAt) {
      // The server deleted blobs: check that it still has ours.
      database.transaction(() {
        blobs.recheckUploads();
        settings.syncBlobsCollectedAt = info.blobsCollectedAt;
      });
    }
    blobs.retryTooLarge(newLimit: info.maxBlobBytes);
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
  }

  /// Blobs whose records must wait: blobs still pending (a failed upload,
  /// or stored since the upload phase), unless their upload has failed too
  /// often. Read again for every page of records, so a record written
  /// during the push cannot overtake a blob stored with it.
  Set<String> _heldBackBlobs() => {
    for (final sha in blobs?.pendingUploads() ?? const <String>[])
      if ((_uploadFailures[sha] ?? 0) < maxHoldBackAttempts) sha,
  };

  /// Pushes live rows parents first and tombstones children first: however
  /// much of a push reaches the server, it never holds content whose parent
  /// it lacks, nor a deleted page or notebook whose content is still live
  /// (which other devices would take for a deletion conflict).
  Future<void> _push(SyncApi api, CancelCheck cancelled) async {
    for (final store in stores) {
      await _pushStore(api, cancelled, store, deleted: false);
    }
    for (final store in stores.toList().reversed) {
      await _pushStore(api, cancelled, store, deleted: true);
    }
  }

  Future<void> _pushStore(
    SyncApi api,
    CancelCheck cancelled,
    SyncableStore store, {
    required bool deleted,
  }) async {
    String? after;
    while (!cancelled()) {
      final rows = store.dirtyRecords(_pushPageSize, after: after, deleted: deleted);
      if (rows.isEmpty) break;
      after = rows.last.id;
      final heldBack = _heldBackBlobs();
      final ready = heldBack.isEmpty
          ? rows
          : [
              for (final r in rows)
                if (!BlobReferences.inValue(r.data).any(heldBack.contains)) r,
            ];
      // Records the API could not send (too large, not encodable) stay dirty.
      final unsent = ready.isEmpty
          ? const <SyncRecord>[]
          : await api.push(ready, since: settings.syncLastSeq);
      if (cancelled()) return;
      final skipped = {for (final r in unsent) r.id};
      store.markClean([
        for (final r in ready)
          if (!skipped.contains(r.id)) (id: r.id, updatedAt: r.updatedAt),
      ]);
      if (rows.length < _pushPageSize) break;
    }
  }

  /// How long (µs) a slice of pulled records may run before it commits and
  /// yields (see [_pull]): a quarter of a frame, as the commit (and the
  /// garbage collector) add to it.
  static const applyBudgetUs = 4000;
}
