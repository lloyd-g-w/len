import 'package:flutter/foundation.dart';

import 'blob_references.dart';
import 'blob_store.dart';
import 'settings_repository.dart';

/// Local blob garbage collection, run occasionally (docs/SYNC_PROTOCOL.md,
/// "Blob garbage collection"): blobs no live row has referenced for
/// [BlobStore.gcGrace] are deleted from this device.
class LocalBlobGc {
  LocalBlobGc({required this.blobs, required this.references, required this.settings});

  final BlobStore blobs;
  final BlobReferences references;
  final SettingsRepository settings;

  /// Minimum time between two runs of [runIfDue].
  static const interval = Duration(days: 1);

  /// Runs [run] unless it ran less than [interval] ago. Never throws.
  Future<List<String>> runIfDue() async {
    final now = blobs.clock.nowMs();
    final last = settings.blobGcLastRun;
    if (last != 0 && now - last < interval.inMilliseconds && now >= last) return const [];
    settings.blobGcLastRun = now;
    try {
      return await run();
    } on Object catch (e, stack) {
      debugPrint('Blob garbage collection failed: $e\n$stack');
      return const [];
    }
  }

  /// Marks newly unreferenced blobs and deletes those past the grace period;
  /// returns the deleted ids.
  Future<List<String>> run() => blobs.collectGarbage(references.all);
}
