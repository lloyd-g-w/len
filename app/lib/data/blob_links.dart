import 'dart:convert';

import 'package:sqlite3/common.dart';

/// The blobs that reference blobs here name (docs/SYNC_PROTOCOL.md,
/// "Reference blobs"): version table blobs and the packs, backgrounds,
/// images and audio in their rows. Noted when such a blob is written or
/// read here (local, never synced), so blob uploads and garbage
/// collection follow a version record into its table without reading
/// blobs (`BlobReferences`).
class BlobLinks {
  BlobLinks(this.db);

  final CommonDatabase db;

  /// Notes that blob [parent] names [children].
  void add(String parent, Iterable<String> children) {
    final insert = db.prepare('INSERT OR IGNORE INTO blob_links (parent, child) VALUES (?, ?)');
    try {
      for (final child in children) {
        insert.execute([parent, child]);
      }
    } finally {
      insert.close();
    }
  }

  /// Whether the blobs [parent] names are noted.
  bool knows(String parent) =>
      db.select('SELECT 1 FROM blob_links WHERE parent = ? LIMIT 1', [parent]).isNotEmpty;

  /// The blobs [parents] name (as far as noted here).
  Set<String> childrenOf(Iterable<String> parents) {
    final list = parents.toList();
    if (list.isEmpty) return const {};
    return {
      for (final row in db.select(
        'SELECT DISTINCT child FROM blob_links WHERE parent IN (SELECT value FROM json_each(?))',
        [jsonEncode(list)],
      ))
        row['child'] as String,
    };
  }

  /// Forgets the links of blobs no longer stored here.
  void prune() =>
      db.execute('DELETE FROM blob_links WHERE parent NOT IN (SELECT sha256 FROM blobs)');
}
