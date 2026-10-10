import 'app_database.dart';

/// Cheap summary of a surface's live strokes and elements, used to tell whether a cached
/// rendering (e.g. a library thumbnail) is still current.
typedef SurfaceFingerprint = ({int count, int version});

/// Read-only queries over stroke metadata that do not load point data.
class SurfaceStats {
  SurfaceStats(this._database);

  final AppDatabase _database;

  /// Number of live strokes and elements on [surfaceId] and their latest
  /// version. Any stroke or text box added, changed, erased or restored
  /// changes the result.
  SurfaceFingerprint fingerprint(String surfaceId) {
    final row = _database.db.select(
      'SELECT SUM(c) AS c, MAX(v) AS v FROM ('
      '  SELECT COUNT(*) AS c, COALESCE(MAX(updated_at), 0) AS v FROM strokes '
      '  WHERE surface_id = ? AND deleted = 0 '
      '  UNION ALL '
      '  SELECT COUNT(*), COALESCE(MAX(updated_at), 0) FROM elements '
      '  WHERE surface_id = ? AND deleted = 0'
      ')',
      [surfaceId, surfaceId],
    ).first;
    return (count: row['c'] as int, version: row['v'] as int);
  }

  /// Number of live pages per notebook (paged notebooks only appear).
  Map<String, int> pageCounts() => {
    for (final row in _database.db.select(
      'SELECT notebook_id, COUNT(*) AS c FROM pages WHERE deleted = 0 GROUP BY notebook_id',
    ))
      row['notebook_id'] as String: row['c'] as int,
  };
}
