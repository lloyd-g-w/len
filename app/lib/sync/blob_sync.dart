import 'package:flutter/foundation.dart';

import '../data/blob_store.dart';
import 'sync_api.dart';
import 'sync_engine.dart';

/// Moves content-addressed blobs between the local [BlobStore] and the
/// sync server (docs/SYNC_PROTOCOL.md, "Blobs").
class BlobSync {
  BlobSync(this.store);

  final BlobStore store;

  /// Uploads every local blob the server does not have yet. Throws
  /// [SyncException] on failure, which aborts the sync cycle before any
  /// record referencing the blob is pushed.
  Future<void> uploadPending(SyncApi api, CancelCheck cancelled) async {
    for (final sha in store.pendingUploads()) {
      if (cancelled()) return;
      final size = store.sizeOf(sha);
      if (size == null || !await store.has(sha)) {
        // Recorded but the file is gone (e.g. wiped by the OS): nothing to
        // send; another device that has it will upload it.
        debugPrint('Blob $sha is missing locally; not uploading');
        store.markUploaded(sha);
        continue;
      }
      if (!await api.hasBlob(sha)) await api.putBlob(sha, store.openRead(sha), length: size);
      if (cancelled()) return;
      store.markUploaded(sha);
    }
  }

  /// Fetches blob [sha] into the store. Returns false if the server does
  /// not have it (yet).
  Future<bool> download(SyncApi api, String sha) async {
    if (await store.has(sha)) return true;
    final bytes = await api.getBlob(sha);
    if (bytes == null) return false;
    try {
      await store.putDownloaded(sha, bytes);
    } on FormatException catch (e) {
      throw SyncException(e.message);
    }
    return true;
  }
}
