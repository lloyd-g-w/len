/// Garbage collection of blobs no live record references.
library;

import 'dart:convert';
import 'dart:io';

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
/// *Reference blobs* (docs/SYNC_PROTOCOL.md, "Reference blobs": the bytes
/// `LR`, format 1, then a zlib stream) reference blobs too: a reference
/// blob that is referenced is inflated and scanned the same way, and so on,
/// so a version record keeps the packs its table blobs name.
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
    // Narrow the race with a client pushing a new reference meanwhile; a
    // blob referenced again loses its mark (a later tombstone starts a new
    // grace period).
    if (due.isNotEmpty) {
      final rescued = referencedAmong(due);
      due = due.difference(rescued);
      rescued.forEach(marks.remove);
    }

    final deleted = <String>[];
    var bytes = 0;
    for (final sha in [...due]) {
      // Re-uploaded meanwhile (a client was told it is stored): keep it.
      if (_newerThan(sha, cutoff)) {
        due.remove(sha);
        continue;
      }
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
  /// mentions, directly or through reference blobs.
  Set<String> referencedAmong(Set<String> candidates) {
    if (candidates.isEmpty) return {};
    final reached = <String>{};
    final open = <String>[];
    void scan(String text) {
      for (final match in _hexRun.allMatches(text)) {
        final run = match[0]!;
        for (var i = 0; i + 64 <= run.length; i++) {
          final sha = run.substring(i, i + 64);
          if (reached.add(sha)) open.add(sha);
        }
      }
    }

    records.forEachLiveData(scan);
    while (open.isNotEmpty) {
      if (_referenceText(open.removeLast()) case final text?) scan(text);
    }
    return reached.intersection(candidates);
  }

  /// The text a stored reference blob [sha] holds; null when [sha] is not
  /// stored or no reference blob.
  String? _referenceText(String sha) {
    final RandomAccessFile file;
    try {
      file = File(blobs.pathFor(sha)).openSync();
    } on FileSystemException {
      return null;
    }
    try {
      final head = file.readSync(3);
      if (head.length < 3 || head[0] != _magic[0] || head[1] != _magic[1] || head[2] != 1) {
        return null;
      }
      final rest = file.readSync(file.lengthSync() - 3);
      return utf8.decode(zlib.decode(rest), allowMalformed: true);
    } on Object {
      return null; // Unreadable or no zlib stream: references nothing.
    } finally {
      file.closeSync();
    }
  }

  /// `LR`: the magic of reference blobs.
  static const _magic = [0x4C, 0x52];

  bool _newerThan(String sha, DateTime cutoff) {
    final modified = blobs.modified(sha);
    return modified != null && modified.isAfter(cutoff);
  }
}
