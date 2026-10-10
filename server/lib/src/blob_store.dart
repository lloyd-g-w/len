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

/// Immutable blobs stored as `<root>/<first 2 hex>/<sha256>`.
///
/// Uploads are written to `<root>/tmp/` under unique names and atomically
/// renamed into place, so concurrent uploads of the same blob are safe and
/// readers never see partial files.
class BlobStore {
  /// Opens (and creates) a store rooted at [root]. Leftover temp files from
  /// interrupted uploads are removed.
  BlobStore.open(this.root) {
    final tmp = Directory(_tmpDir);
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    tmp.createSync(recursive: true);
  }

  /// Directory holding all blobs.
  final String root;

  static final _shaPattern = RegExp(r'^[0-9a-f]{64}$');
  static final _random = Random.secure();
  static var _counter = 0;

  /// Whether [sha] is a valid blob key (64 lowercase hex chars).
  static bool isValidSha(String sha) => _shaPattern.hasMatch(sha);

  String get _tmpDir => '$root/tmp';

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

  /// Streams the contents of the blob [sha] (which must exist).
  Stream<List<int>> openRead(String sha) => File(pathFor(sha)).openRead();

  /// Stores [data] as blob [sha] and returns its size.
  ///
  /// The data is hashed while being written to a temp file. Throws
  /// [BlobTooLargeException] once more than [maxBytes] arrive and
  /// [BlobHashMismatchException] if the hash differs from [sha]; in both
  /// cases nothing is stored. Storing an existing blob is a no-op.
  Future<int> put(String sha, Stream<List<int>> data, {required int maxBytes}) async {
    final finalPath = pathFor(sha);
    final existing = size(sha);
    if (existing != null) return existing;

    final tmp = File('$_tmpDir/$sha.$pid.${_counter++}.${_random.nextInt(1 << 32)}');
    final digestSink = _DigestSink();
    final hasher = sha256.startChunkedConversion(digestSink);
    final out = tmp.openWrite();
    var length = 0;
    var committed = false;
    try {
      await for (final chunk in data) {
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
