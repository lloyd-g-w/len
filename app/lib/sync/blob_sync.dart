import 'package:flutter/foundation.dart';

import '../data/blob_store.dart';
import 'sync_api.dart';
import 'sync_engine.dart';

/// Outcome of [BlobSync.uploadPending].
class BlobUploadReport {
  BlobUploadReport({this.failed = const {}, this.error});

  /// Blobs whose upload failed for a reason worth retrying (network, server
  /// error); they stay pending.
  final Set<String> failed;

  /// The first such failure, for the sync status.
  final String? error;
}

/// Moves content-addressed blobs between the local [BlobStore] and the
/// sync server (docs/SYNC_PROTOCOL.md, "Blobs").
class BlobSync {
  BlobSync(this.store);

  final BlobStore store;

  /// Uploads the [referenced] local blobs the server does not have yet;
  /// blobs no live row references are not worth sending.
  ///
  /// One blob cannot stall the others: a blob larger than [maxBlobBytes]
  /// (the server's advertised limit, if known) or refused with 413 is
  /// marked too large and skipped from then on; any other failure of a
  /// blob's upload (an error status, or the connection breaking during a
  /// long upload) is reported in [BlobUploadReport.failed] and retried on
  /// the next sync. Throws [SyncException] when the server is unreachable
  /// (checking whether it has a blob fails) or rejects the token, which
  /// would fail the rest of the sync as well.
  Future<BlobUploadReport> uploadPending(
    SyncApi api,
    CancelCheck cancelled, {
    required Set<String> Function() referenced,
    int? maxBlobBytes,
  }) async {
    final pending = store.pendingUploads();
    if (pending.isEmpty) return BlobUploadReport();
    final live = referenced();
    final failed = <String>{};
    String? error;
    for (final sha in pending) {
      if (cancelled()) break;
      if (!live.contains(sha)) continue;
      final size = store.sizeOf(sha);
      if (size == null || !await store.has(sha)) {
        // Recorded but the file is gone (e.g. wiped by the OS): nothing to
        // send; another device that has it will upload it.
        debugPrint('Blob $sha is missing locally; not uploading');
        store.markUploaded(sha);
        continue;
      }
      if (maxBlobBytes != null && size > maxBlobBytes) {
        store.markTooLarge(sha, maxBlobBytes);
        continue;
      }
      // An unreachable server fails here, before any upload: give up then.
      final onServer = await _rethrowUnlessBlobSpecific(() => api.hasBlob(sha));
      if (onServer == null) {
        failed.add(sha);
        error ??= _lastError;
        continue;
      }
      if (!onServer) {
        final uploaded = await _rethrowUnlessBlobSpecific(
          () => _put(api, sha, size, maxBlobBytes: maxBlobBytes),
          network: true,
        );
        if (uploaded == null) {
          failed.add(sha);
          error ??= _lastError;
          continue;
        }
        if (!uploaded) continue; // Too large.
      }
      if (cancelled()) break;
      store.markUploaded(sha);
    }
    return BlobUploadReport(failed: failed, error: error);
  }

  String? _lastError;

  /// Runs a request about one blob; returns null if it failed in a way
  /// specific to that blob (an error status; with [network] also a broken
  /// connection, as a long upload may hit) and rethrows otherwise.
  Future<T?> _rethrowUnlessBlobSpecific<T>(
    Future<T> Function() request, {
    bool network = false,
  }) async {
    try {
      return await request();
    } on SyncException catch (e) {
      if (e.kind == SyncFailure.auth || (e.kind == SyncFailure.network && !network)) rethrow;
      debugPrint('Blob upload failed: ${e.message}');
      _lastError = e.message;
      return null;
    }
  }

  /// Uploads one blob; returns false if the server refused it as too large
  /// (it is then marked, and records referencing it sync without it).
  Future<bool> _put(SyncApi api, String sha, int size, {int? maxBlobBytes}) async {
    try {
      await api.putBlob(sha, store.openRead(sha), length: size);
      return true;
    } on SyncException catch (e) {
      if (e.kind != SyncFailure.tooLarge) rethrow;
      store.markTooLarge(sha, maxBlobBytes);
      return false;
    }
  }

  /// Fetches blob [sha] into the store. Returns false if the server does
  /// not have it (yet). [fromCurrentServer] tells whether [api] still leads
  /// to the server this device syncs with (see [BlobStore.putDownloaded]).
  Future<bool> download(SyncApi api, String sha, {bool Function()? fromCurrentServer}) async {
    if (await store.has(sha)) return true;
    final bytes = await api.getBlob(sha);
    if (bytes == null) return false;
    try {
      await store.putDownloaded(sha, bytes, fromCurrentServer: fromCurrentServer);
    } on FormatException catch (e) {
      throw SyncException(e.message);
    }
    return true;
  }
}
