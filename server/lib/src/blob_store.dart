/// Content-addressed blob storage on the local filesystem.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Thrown by [BlobStore.put] when the data exceeds the size limit.
class BlobTooLargeException implements Exception {
  BlobTooLargeException(this.maxBytes);

  final int maxBytes;

  @override
  String toString() => 'BlobTooLargeException: more than $maxBytes bytes';
}

/// Thrown by [BlobStore.put] when the data does not hash to the given sha256.
class BlobHashMismatchException implements Exception {
  BlobHashMismatchException(this.expected, this.actual);

  final String expected;
  final String actual;

  @override
  String toString() => 'BlobHashMismatchException: expected $expected, got $actual';
}

/// Thrown by [BlobStore.put] when no data arrives for longer than the idle
/// timeout (a stalled upload).
class BlobUploadStalledException implements Exception {
  BlobUploadStalledException(this.idleTimeout);

  final Duration idleTimeout;

  @override
  String toString() => 'BlobUploadStalledException: no data for $idleTimeout';
}

/// Immutable blobs stored as `<root>/<first 2 hex>/<sha256>`.
///
/// Uploads are written to `<root>/tmp/` under unique names and atomically
/// renamed into place, so concurrent uploads of the same blob are safe and
/// readers never see partial files.
class BlobStore {
  /// Opens (and creates) a store rooted at [root]. Temp files of
  /// interrupted uploads older than [staleTmpAge] are removed; younger ones
  /// may belong to an upload in progress in another server process sharing
  /// the directory, so they are left alone.
  BlobStore.open(this.root, {Duration staleTmpAge = defaultStaleTmpAge}) {
    Directory(_tmpDir).createSync(recursive: true);
    removeStaleTmpFiles(staleTmpAge);
  }

  /// Default age after which a temp file counts as abandoned.
  static const defaultStaleTmpAge = Duration(days: 1);

  /// Directory holding all blobs.
  final String root;

  static final _shaPattern = RegExp(r'^[0-9a-f]{64}$');
  static final _random = Random.secure();
  static var _counter = 0;

  /// Whether [sha] is a valid blob key (64 lowercase hex chars).
  static bool isValidSha(String sha) => _shaPattern.hasMatch(sha);

  String get _tmpDir => '$root/tmp';

  /// Deletes temp files last modified more than [age] ago (abandoned
  /// uploads) and returns how many were removed. An upload in progress keeps
  /// writing to its temp file, so its modification time stays recent.
  int removeStaleTmpFiles(Duration age) {
    final cutoff = DateTime.now().subtract(age);
    var removed = 0;
    for (final entity in Directory(_tmpDir).listSync(followLinks: false)) {
      try {
        if (entity.statSync().modified.isBefore(cutoff)) {
          entity.deleteSync(recursive: true);
          removed++;
        }
      } on FileSystemException {
        // Renamed or removed concurrently: nothing to clean up.
      }
    }
    return removed;
  }

  /// Final path of the blob [sha].
  String pathFor(String sha) {
    _checkSha(sha);
    return '$root/${sha.substring(0, 2)}/$sha';
  }

  /// Whether the blob [sha] is stored.
  bool has(String sha) => File(pathFor(sha)).existsSync();

  /// Size in bytes of the blob [sha], or `null` if it is not stored.
  int? size(String sha) {
    final stat = FileStat.statSync(pathFor(sha));
    return stat.type == FileSystemEntityType.file ? stat.size : null;
  }

  /// Ids of all stored blobs (in no particular order).
  Iterable<String> list() sync* {
    final dir = Directory(root);
    if (!dir.existsSync()) return;
    for (final sub in dir.listSync(followLinks: false)) {
      final name = sub.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      if (sub is! Directory || name.length != 2) continue;
      for (final file in sub.listSync(followLinks: false)) {
        final sha = file.uri.pathSegments.last;
        if (file is File && isValidSha(sha) && sha.startsWith(name)) yield sha;
      }
    }
  }

  /// Last modification time of the blob [sha] (when it was stored or last
  /// re-uploaded), or `null` if it is not stored.
  DateTime? modified(String sha) {
    final stat = FileStat.statSync(pathFor(sha));
    return stat.type == FileSystemEntityType.file ? stat.modified : null;
  }

  /// Deletes the blob [sha]; returns whether it existed.
  bool delete(String sha) {
    try {
      File(pathFor(sha)).deleteSync();
      return true;
    } on PathNotFoundException {
      return false;
    }
  }

  /// Streams the contents of the blob [sha] (which must exist).
  Stream<List<int>> openRead(String sha) => File(pathFor(sha)).openRead();

  /// Stores [data] as blob [sha] and returns its size.
  ///
  /// The data is hashed while being written to a temp file. Throws
  /// [BlobTooLargeException] once more than [maxBytes] arrive and
  /// [BlobHashMismatchException] if the hash differs from [sha]; in both
  /// cases nothing is stored. If [idleTimeout] is given and no data arrives
  /// for that long, the upload is abandoned with
  /// [BlobUploadStalledException]. Storing an existing blob is a no-op.
  Future<int> put(
    String sha,
    Stream<List<int>> data, {
    required int maxBytes,
    Duration? idleTimeout,
  }) async {
    final finalPath = pathFor(sha);
    final existing = size(sha);
    if (existing != null) {
      // A fresh modification time protects a re-uploaded blob from garbage
      // collection for the grace period (see `BlobGc`).
      _touch(finalPath);
      return existing;
    }

    final tmp = File('$_tmpDir/$sha.$pid.${_counter++}.${_random.nextInt(1 << 32)}');
    final digestSink = _DigestSink();
    final hasher = sha256.startChunkedConversion(digestSink);
    final out = tmp.openWrite();
    var length = 0;
    var committed = false;
    try {
      final chunks = idleTimeout == null
          ? data
          : data.timeout(
              idleTimeout,
              onTimeout: (sink) => sink
                ..addError(BlobUploadStalledException(idleTimeout))
                ..close(),
            );
      await for (final chunk in chunks) {
        length += chunk.length;
        if (length > maxBytes) throw BlobTooLargeException(maxBytes);
        hasher.add(chunk);
        out.add(chunk);
      }
      hasher.close();
      await out.flush();
      await out.close();
      final actual = digestSink.value.toString();
      if (actual != sha) throw BlobHashMismatchException(sha, actual);
      await Directory(File(finalPath).parent.path).create(recursive: true);
      await tmp.rename(finalPath);
      committed = true;
      return length;
    } finally {
      if (!committed) {
        await out.close().catchError((Object _) {});
        if (tmp.existsSync()) await tmp.delete();
      }
    }
  }

  static void _touch(String path) {
    try {
      File(path).setLastModifiedSync(DateTime.now());
    } on FileSystemException {
      // Read-only storage or a concurrent deletion: not worth failing for.
    }
  }

  static void _checkSha(String sha) {
    if (!isValidSha(sha)) throw ArgumentError.value(sha, 'sha', 'not a sha256 hex string');
  }
}

/// Captures the single digest emitted by a chunked hash conversion.
class _DigestSink implements Sink<Digest> {
  Digest? _value;

  Digest get value => _value!;

  @override
  void add(Digest data) => _value = data;

  @override
  void close() {}
}
