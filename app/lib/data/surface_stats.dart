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
    final row = _database.select(
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

  /// The newest version (ms) of the ink and elements, erased ones too, on
  /// the live pages of notebook [notebookId] written by another device
  /// than [deviceId], or 0: the newest of theirs this device has seen.
  int newestElsewhere(String notebookId, {required String deviceId}) {
    final row = _database.select(
      'SELECT MAX(v) AS v FROM ('
      '  SELECT MAX(s.updated_at) AS v FROM pages p JOIN strokes s ON s.surface_id = p.id '
      '  WHERE p.notebook_id = ?1 AND p.deleted = 0 AND s.device_id != ?2 '
      '  UNION ALL '
      '  SELECT MAX(e.updated_at) FROM pages p JOIN elements e ON e.surface_id = p.id '
      '  WHERE p.notebook_id = ?1 AND p.deleted = 0 AND e.device_id != ?2'
      ')',
      [notebookId, deviceId],
    ).first;
    return row['v'] as int? ?? 0;
  }

  /// The live page of notebook [notebookId] holding the newest ink or
  /// element written by another device than [deviceId] after [after] (a
  /// version, ms), or null (UX_AUDIT R16-4: where the notebook was last
  /// written elsewhere).
  String? pageWrittenElsewhere(String notebookId, {required String deviceId, required int after}) {
    final rows = _database.select(
      'SELECT page FROM ('
      '  SELECT s.surface_id AS page, s.updated_at AS v FROM pages p '
      '  JOIN strokes s ON s.surface_id = p.id '
      '  WHERE p.notebook_id = ? AND p.deleted = 0 AND s.deleted = 0 '
      '    AND s.device_id != ? AND s.updated_at > ? '
      '  UNION ALL '
      '  SELECT e.surface_id, e.updated_at FROM pages p '
      '  JOIN elements e ON e.surface_id = p.id '
      '  WHERE p.notebook_id = ? AND p.deleted = 0 AND e.deleted = 0 '
      '    AND e.device_id != ? AND e.updated_at > ? '
      ') ORDER BY v DESC LIMIT 1',
      [notebookId, deviceId, after, notebookId, deviceId, after],
    );
    return rows.isEmpty ? null : rows.first['page'] as String;
  }
}
