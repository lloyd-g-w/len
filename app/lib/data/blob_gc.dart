import 'package:flutter/foundation.dart';

import 'blob_references.dart';
import 'blob_store.dart';
import 'settings_repository.dart';
import 'tombstone_payloads.dart';

/// Local blob garbage collection, run occasionally (docs/SYNC_PROTOCOL.md,
/// "Blob garbage collection"): blobs no live row (nor a recent tombstone,
/// see [TombstonePayloads]) has referenced for [BlobStore.gcGrace] are
/// deleted from this device. Also drops the payloads of old tombstones.
class LocalBlobGc {
  LocalBlobGc({
    required this.blobs,
    required this.references,
    required this.settings,
    this.tombstones,
    this.prune,
  });

  final BlobStore blobs;
  final BlobReferences references;
  final SettingsRepository settings;

  /// Payloads of old tombstones are dropped first when set.
  final TombstonePayloads? tombstones;

  /// Drops what no longer needs keeping (old versions) before a run.
  final void Function()? prune;

  /// How long after launch the app first calls [runIfDue].
  static const startDelay = Duration(seconds: 20);

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
  Future<List<String>> run() async {
    final now = blobs.clock.nowMs();
    prune?.call();
    await tombstones?.purge(now);
    final deleted = await blobs.collectGarbage(
      () => references.kept(now),
      stillReferenced: (sha) => references.keeps(sha, now),
    );
    if (deleted.isNotEmpty) references.links.prune();
    return deleted;
  }
}
