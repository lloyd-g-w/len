import 'app_database.dart';

/// Files whose copies here "Free up" removed (Settings → Storage), with
/// their MIME type: local only, never synced. Only for these does a
/// server answering "not found" mean a loss (a file another device hasn't
/// uploaded yet is merely late), and a server restored from an older
/// backup is checked for them (`FreedFiles`). A file stored here again
/// leaves the list; one no row references any more is forgotten by
/// garbage collection.
class FreedBlobs {
  FreedBlobs(this.database);

  final AppDatabase database;

  /// Notes that blob [sha] of [mime] was freed at [atMs].
  void add(String sha, String mime, int atMs) => database.db.execute(
    'INSERT OR REPLACE INTO freed_blobs (sha256, mime, freed_at) VALUES (?, ?, ?)',
    [sha, mime, atMs],
  );

  /// Blob [sha] is stored here again (or its removal failed).
  void remove(String sha) => database.db.execute('DELETE FROM freed_blobs WHERE sha256 = ?', [sha]);

  /// Whether blob [sha] was freed and not stored here since.
  bool contains(String sha) => mimeOf(sha) != null;

  /// The MIME type of freed blob [sha], or null if it wasn't freed.
  String? mimeOf(String sha) =>
      database.db.select('SELECT mime FROM freed_blobs WHERE sha256 = ?', [
            sha,
          ]).firstOrNull?['mime']
          as String?;

  /// Every freed blob.
  Set<String> all() => {
    for (final r in database.db.select('SELECT sha256 FROM freed_blobs')) r['sha256'] as String,
  };

  /// Forgets freed blobs [live] (the ids rows reference) doesn't contain.
  void keepOnly(Set<String> live) {
    for (final sha in all()) {
      if (!live.contains(sha)) remove(sha);
    }
  }
}
