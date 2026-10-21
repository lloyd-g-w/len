import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../blob_store.dart';

/// Blobs of a version made in one turn ([VersionSnapshots.buildNow]): their
/// ids are known at once (hashed here), their bytes stored by [write] once
/// that turn is over (storing takes turns). Until then they are
/// [BlobStore.coming]: sync holds back what names them.
class PendingBlobs {
  PendingBlobs(this.blobs);

  final BlobStore blobs;

  final Map<String, ({Uint8List bytes, String mime, List<void Function()> stored})> _blobs = {};

  /// Notes [bytes] to store; returns their id. [stored] runs once they are.
  String put(Uint8List bytes, {required String mime, void Function(String sha)? stored}) {
    final sha = sha256.convert(bytes).toString();
    final entry = _blobs.putIfAbsent(sha, () {
      blobs.willStore(sha);
      return (bytes: bytes, mime: mime, stored: []);
    });
    if (stored != null) entry.stored.add(() => stored(sha));
    return sha;
  }

  /// Stores every blob noted.
  Future<void> write() async {
    try {
      for (final MapEntry(key: sha, value: blob) in _blobs.entries.toList()) {
        await blobs.putBytes(blob.bytes, mime: blob.mime);
        for (final done in blob.stored) {
          done();
        }
        _blobs.remove(sha);
        blobs.arrived(sha);
      }
    } finally {
      discard();
    }
  }

  /// Forgets the blobs not stored (what named them was not saved, or
  /// storing them failed): no longer [BlobStore.coming].
  void discard() {
    _blobs.keys.forEach(blobs.arrived);
    _blobs.clear();
  }
}
