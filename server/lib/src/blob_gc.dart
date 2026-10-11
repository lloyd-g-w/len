/// Garbage collection of blobs no live record references.
library;

import 'blob_store.dart';
import 'record_store.dart';

/// Outcome of one [BlobGc.run].
class BlobGcResult {
  const BlobGcResult({
    required this.stored,
    required this.referenced,
    required this.waiting,
    required this.deleted,
    required this.deletedBytes,
  });

  /// Number of blobs stored before the run.
  final int stored;

  /// Number of stored blobs some live record references.
  final int referenced;

  /// Unreferenced blobs still within the grace period: sha256 → since when
  /// they have been unreferenced.
  final Map<String, DateTime> waiting;

  /// Blobs deleted (or, in a dry run, that would have been deleted).
  final List<String> deleted;

  /// Total size of [deleted].
  final int deletedBytes;
}

/// Deletes blobs that no live record has referenced for a grace period.
///
/// The server does not understand record payloads, so references are found
/// by scanning the JSON `data` of every live (not deleted) record for runs
/// of lowercase hex characters and checking every 64-character window of
/// them against the stored blobs. This needs no protocol change and keeps
/// working when the app adds new kinds of references. It errs on the safe
/// side: any string that happens to equal a stored blob's sha256 keeps that
/// blob, and a client that stored references in some other encoding would
/// have them collected (current clients write plain `<sha256>` strings).
///
/// A blob is deleted only if it was found unreferenced by an earlier run at
/// least [grace] ago, is still unreferenced (checked again right before
/// deleting), and its file was not stored or re-uploaded within [grace]
/// either. The grace period covers devices that were offline with records
/// still referencing a blob; and because `/v1/health` reports
/// `blobsCollectedAt`, clients re-check (and if needed re-upload) their
/// blobs after a collection.
class BlobGc {
  BlobGc(this.records, this.blobs, {this.grace = defaultGrace});

  /// Default grace period.
  static const defaultGrace = Duration(days: 30);

  final RecordStore records;
  final BlobStore blobs;
  final Duration grace;

  static final _hexRun = RegExp('[0-9a-f]{64,}');

  /// Marks newly unreferenced blobs and deletes those past the grace period.
  /// With [dryRun] nothing is changed (neither files nor marks); `deleted`
  /// then lists what would be deleted given the existing marks.
  BlobGcResult run({bool dryRun = false, DateTime? now}) {
    final time = now ?? DateTime.now();
    final cutoff = time.subtract(grace);
    final stored = blobs.list().toSet();
    final referenced = referencedAmong(stored);

    final previous = records.unreferencedBlobs();
    final marks = <String, int>{
      for (final sha in stored.difference(referenced))
        sha: previous[sha] ?? time.millisecondsSinceEpoch,
    };
    var due = {
      for (final MapEntry(key: sha, value: since) in marks.entries)
        if (since <= cutoff.millisecondsSinceEpoch && !_newerThan(sha, cutoff)) sha,
    };
    // Narrow the race with a client pushing a new reference meanwhile.
    if (due.isNotEmpty) due = due.difference(referencedAmong(due));

    final deleted = <String>[];
    var bytes = 0;
    for (final sha in due) {
      final size = blobs.size(sha) ?? 0;
      if (dryRun || blobs.delete(sha)) {
        deleted.add(sha);
        bytes += size;
      }
      marks.remove(sha);
    }
    if (!dryRun) {
      records.setUnreferencedBlobs(marks);
      if (deleted.isNotEmpty) records.blobsCollectedAt = time.millisecondsSinceEpoch;
      blobs.removeStaleTmpFiles(BlobStore.defaultStaleTmpAge);
    }
    return BlobGcResult(
      stored: stored.length,
      referenced: referenced.length,
      waiting: {
        for (final MapEntry(key: sha, value: since) in marks.entries)
          if (!due.contains(sha)) sha: DateTime.fromMillisecondsSinceEpoch(since),
      },
      deleted: deleted,
      deletedBytes: bytes,
    );
  }

  /// The blobs among [candidates] that the data of some live record
  /// mentions.
  Set<String> referencedAmong(Set<String> candidates) {
    final found = <String>{};
    if (candidates.isEmpty) return found;
    records.forEachLiveData((data) {
      for (final match in _hexRun.allMatches(data)) {
        final run = match[0]!;
        for (var i = 0; i + 64 <= run.length; i++) {
          final sha = run.substring(i, i + 64);
          if (candidates.contains(sha)) found.add(sha);
        }
      }
    });
    return found;
  }

  bool _newerThan(String sha, DateTime cutoff) {
    final modified = blobs.modified(sha);
    return modified != null && modified.isAfter(cutoff);
  }
}
