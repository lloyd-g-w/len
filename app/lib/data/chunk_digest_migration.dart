import 'package:sqlite3/common.dart';

import '../domain/chunk_digest.dart';
import '../domain/stroke_chunks.dart';
import 'stroke_queries.dart';

/// Version 10: chunk digests. Every `stroke_chunks` / `element_chunks` row
/// carries its item's hash (`ChunkDigest`), so a chunk's content digest is
/// one aggregate query away (persistent level-of-detail rasters are keyed
/// by it). Rebuilds both indexes from the live rows, so the chunks they
/// list are exactly those memory computes (older rows indexed whole
/// bounding boxes) and the digests agree.
abstract final class ChunkDigestMigration {
  static void migrate(CommonDatabase db) {
    db.execute('ALTER TABLE stroke_chunks ADD COLUMN digest INTEGER NOT NULL DEFAULT 0');
    db.execute('ALTER TABLE element_chunks ADD COLUMN digest INTEGER NOT NULL DEFAULT 0');
    db.execute('DELETE FROM stroke_chunks');
    db.execute('DELETE FROM element_chunks');
    final strokeRow = db.prepare(
      'INSERT OR IGNORE INTO stroke_chunks (surface_id, cx, cy, stroke_id, digest) '
      'VALUES (?, ?, ?, ?, ?)',
    );
    final elementRow = db.prepare(
      'INSERT OR IGNORE INTO element_chunks (surface_id, cx, cy, element_id, digest) '
      'VALUES (?, ?, ?, ?, ?)',
    );
    try {
      // Paged by rowid, so a large database is never decoded all at once.
      var after = -1;
      while (true) {
        final rows = db.select(
          'SELECT rowid AS r, * FROM strokes WHERE deleted = 0 AND rowid > ? '
          'ORDER BY rowid LIMIT 500',
          [after],
        );
        if (rows.isEmpty) break;
        after = rows.last['r'] as int;
        for (final s in rows.map(StrokeQueries.rowToStroke).nonNulls) {
          final digest = ChunkDigest.ofStroke(s.id);
          for (final key in StrokeChunks.of(s)) {
            strokeRow.execute([s.surfaceId, key.x, key.y, s.id, digest]);
          }
        }
      }
      final elements = db.select('SELECT * FROM elements WHERE deleted = 0');
      for (final e in elements.map(StrokeQueries.rowToElement).nonNulls) {
        final digest = ChunkDigest.ofElement(e);
        for (final key in ElementChunks.of(e)) {
          elementRow.execute([e.surfaceId, key.x, key.y, e.id, digest]);
        }
      }
    } finally {
      strokeRow.close();
      elementRow.close();
    }
  }
}
