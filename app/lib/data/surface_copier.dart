import '../domain/chunk_grid.dart';
import '../domain/stroke.dart';
import 'stroke_repository.dart';

/// Whole-surface stroke operations used by page management.
class SurfaceCopier {
  SurfaceCopier(this.strokes);

  final StrokeRepository strokes;

  /// Every chunk any surface could plausibly use.
  static const _everywhere = ChunkRange(-1 << 22, -1 << 22, 1 << 22, 1 << 22);

  /// All live strokes of [surfaceId].
  List<Stroke> loadAll(String surfaceId) =>
      strokes.loadChunks(surfaceId, strokes.populatedChunks(surfaceId, _everywhere));

  /// Copies every live stroke of [from] onto surface [to] with new ids.
  ///
  /// Works on whole rows, so stroke columns this class does not know about
  /// (e.g. added by later migrations) are copied too.
  int copy({required String from, required String to}) {
    final db = strokes.db;
    return strokes.database.transaction(() {
      db.execute('DROP TABLE IF EXISTS temp.surface_copy');
      db.execute(
        'CREATE TEMP TABLE surface_copy AS SELECT * FROM strokes WHERE surface_id = ? AND deleted = 0',
        [from],
      );
      final ids = db
          .select('SELECT id FROM temp.surface_copy')
          .map((r) => r['id'] as String)
          .toList();
      final now = strokes.clock.nowMs();
      for (final oldId in ids) {
        final newId = strokes.clock.newId();
        db.execute(
          'UPDATE temp.surface_copy SET id = ?, surface_id = ?, updated_at = ?, device_id = ?, '
          'dirty = 1 WHERE id = ?',
          [newId, to, now, strokes.deviceId, oldId],
        );
        db.execute(
          'INSERT OR IGNORE INTO stroke_chunks (surface_id, cx, cy, stroke_id) '
          'SELECT ?, cx, cy, ? FROM stroke_chunks WHERE stroke_id = ?',
          [to, newId, oldId],
        );
      }
      db.execute('INSERT INTO strokes SELECT * FROM temp.surface_copy');
      db.execute('DROP TABLE temp.surface_copy');
      return ids.length;
    });
  }
}
