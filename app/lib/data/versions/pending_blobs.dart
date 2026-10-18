import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../blob_store.dart';

/// Blobs of a version made in one turn ([VersionSnapshots.buildNow]): their
/// ids are known at once (hashed here), their bytes stored by [write] once
/// that turn is over (storing takes turns).
class PendingBlobs {
  PendingBlobs(this.blobs);

  final BlobStore blobs;

  final Map<String, ({Uint8List bytes, String mime, List<void Function()> stored})> _blobs = {};

  /// Notes [bytes] to store; returns their id. [stored] runs once they are.
  String put(Uint8List bytes, {required String mime, void Function(String sha)? stored}) {
    final sha = sha256.convert(bytes).toString();
    final entry = _blobs.putIfAbsent(sha, () => (bytes: bytes, mime: mime, stored: []));
    if (stored != null) entry.stored.add(() => stored(sha));
    return sha;
  }

  /// Stores every blob noted.
  Future<void> write() async {
    for (final blob in _blobs.values) {
      await blobs.putBytes(blob.bytes, mime: blob.mime);
      for (final done in blob.stored) {
        done();
      }
    }
    _blobs.clear();
  }
}
