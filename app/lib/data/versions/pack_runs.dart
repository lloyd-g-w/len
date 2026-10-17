import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/common.dart';

import '../blob_store.dart';
import 'version_packs.dart';

/// The packs made before, by what went into them (`version_runs`, local):
/// a run of a surface's items cut as [VersionPacks.cut] does is packed
/// once, and found again by its key in every later version while it is
/// unchanged, so a version after one stroke on a canvas of 50,000 encodes
/// one pack, not all of them (docs/PERFORMANCE.md, round 13).
class PackRuns {
  PackRuns(this._db, this._blobs);

  final CommonDatabase _db;
  final BlobStore _blobs;

  /// The key of a run of strokes [ids]: a stroke never changes under its
  /// id, so its id names its content.
  static String strokesKey(Iterable<String> ids) => _key('s', ids);

  /// The key of a run of elements: their ids and versions ([parts], in
  /// order, `id@updatedAt`), as elements are edited in place.
  static String elementsKey(Iterable<String> parts) => _key('e', parts);

  static String _key(String kind, Iterable<String> parts) =>
      sha256.convert(utf8.encode('${VersionPacks.format}$kind\n${parts.join('\n')}')).toString();

  /// The pack made of the run [key] before, while it is still stored.
  String? find(String key) {
    final sha =
        _db.select('SELECT sha FROM version_runs WHERE key = ?', [key]).firstOrNull?['sha']
            as String?;
    if (sha == null) return null;
    if (_blobs.sizeOf(sha) != null) return sha;
    _db.execute('DELETE FROM version_runs WHERE key = ?', [key]);
    return null;
  }

  /// Packs [items] (the run [key]) and remembers it.
  Future<String> put(String key, List<PackItem> items) async {
    final sha = await _blobs.putBytes(VersionPacks.encode(items), mime: VersionPacks.mime);
    _db.execute('INSERT OR REPLACE INTO version_runs (key, sha) VALUES (?, ?)', [key, sha]);
    return sha;
  }
}
