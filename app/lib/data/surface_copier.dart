import '../domain/chunk_grid.dart';
import '../domain/stroke.dart';
import '../domain/surface_element.dart';
import 'element_repository.dart';
import 'stroke_repository.dart';

/// Whole-surface content operations (strokes and, when [elements] is
/// given, elements such as text boxes) used by page management, previews
/// and export.
class SurfaceCopier {
  SurfaceCopier(this.strokes, {this.elements});

  final StrokeRepository strokes;
  final ElementRepository? elements;

  /// Every chunk any surface could plausibly use.
  static const _everywhere = ChunkRange(-1 << 22, -1 << 22, 1 << 22, 1 << 22);

  /// All live strokes of [surfaceId].
  List<Stroke> loadAll(String surfaceId) =>
      strokes.loadChunks(surfaceId, strokes.populatedChunks(surfaceId, _everywhere));

  /// All live elements of [surfaceId] (none without [elements]).
  List<SurfaceElement> loadAllElements(String surfaceId) {
    final repo = elements;
    if (repo == null) return const [];
    return repo.loadChunks(surfaceId, repo.populatedChunks(surfaceId, _everywhere));
  }

  /// Copies every live stroke (and element) of [from] onto surface [to]
  /// with new ids; returns the number of strokes copied.
  ///
  /// Works on whole rows, so columns this class does not know about (e.g.
  /// added by later migrations) are copied too.
  int copy({required String from, required String to}) {
    return strokes.database.transaction(() {
      if (elements != null) _copyRows('elements', 'element_chunks', 'element_id', from, to);
      return _copyRows('strokes', 'stroke_chunks', 'stroke_id', from, to);
    });
  }

  /// Copies the live rows of [table] (a trusted constant) on [from] to
  /// [to], with their [chunks] index entries.
  int _copyRows(String table, String chunks, String idColumn, String from, String to) {
    final db = strokes.db;
    return strokes.database.transaction(() {
      db.execute('DROP TABLE IF EXISTS temp.surface_copy');
      db.execute(
        'CREATE TEMP TABLE surface_copy AS SELECT * FROM $table WHERE surface_id = ? AND deleted = 0',
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
          'INSERT OR IGNORE INTO $chunks (surface_id, cx, cy, $idColumn) '
          'SELECT ?, cx, cy, ? FROM $chunks WHERE $idColumn = ?',
          [to, newId, oldId],
        );
      }
      db.execute('INSERT INTO $table SELECT * FROM temp.surface_copy');
      db.execute('DROP TABLE temp.surface_copy');
      return ids.length;
    });
  }
}
