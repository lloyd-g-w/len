import 'app_database.dart';

/// Cheap summary of a surface's live strokes, used to tell whether a cached
/// rendering (e.g. a library thumbnail) is still current.
typedef SurfaceFingerprint = ({int count, int version});

/// Read-only queries over stroke metadata that do not load point data.
class SurfaceStats {
  SurfaceStats(this._database);

  final AppDatabase _database;

  /// Number of live strokes on [surfaceId] and their latest version. Any
  /// stroke added, erased or restored changes the result.
  SurfaceFingerprint fingerprint(String surfaceId) {
    final row = _database.db.select(
      'SELECT COUNT(*) AS c, COALESCE(MAX(updated_at), 0) AS v FROM strokes '
      'WHERE surface_id = ? AND deleted = 0',
      [surfaceId],
    ).first;
    return (count: row['c'] as int, version: row['v'] as int);
  }
}
