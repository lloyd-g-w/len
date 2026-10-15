import '../data/blob_references.dart';
import 'sync_controller.dart';

/// Files the notebooks here show that only the sync server holds: their
/// copies here were removed (Settings → Storage, "Free up") or never
/// downloaded. Before this device leaves its server (sync turned off,
/// another server) they are downloaded, or they would be out of reach —
/// and another server would never get them.
class ServerOnlyFiles {
  ServerOnlyFiles(this.sync);

  final SyncController sync;

  /// Downloads in a row that fail before the rest are given up (offline).
  static const int maxFailuresInARow = 3;

  /// The files live rows reference that are not stored here.
  Set<String> find() {
    final blobs = sync.engine.blobs;
    if (blobs == null) return const {};
    return {
      for (final sha in BlobReferences(sync.engine.database).all())
        if (blobs.sizeOf(sha) == null) sha,
    };
  }

  /// Downloads [shas] from the server, telling [onProgress] how many are
  /// done; returns how many could not be. [check] may throw to stop
  /// (cancelled) between files. After [maxFailuresInARow] failures in a
  /// row the rest count as not downloaded.
  Future<int> download(
    Set<String> shas, {
    void Function(int done, int total)? onProgress,
    void Function()? check,
  }) async {
    var done = 0, failed = 0, inARow = 0;
    for (final sha in shas) {
      check?.call();
      if (inARow >= maxFailuresInARow) {
        failed++;
      } else if (await sync.fetchBlob(sha)) {
        inARow = 0;
      } else {
        failed++;
        inARow++;
      }
      onProgress?.call(++done, shas.length);
    }
    return failed;
  }
}
