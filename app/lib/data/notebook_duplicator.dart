import '../domain/notebook.dart';
import 'notebook_repository.dart';
import 'row_copier.dart';

/// Deep-copies a notebook: its row, its pages and every live stroke and
/// element (with their chunk indexes), all under new ids and marked dirty
/// for sync.
///
/// Rows are copied column-by-column ([RowCopier]), so attributes added by
/// later migrations (page templates, stroke kinds, …) are carried over.
class NotebookDuplicator {
  NotebookDuplicator(this._notebooks);

  final NotebookRepository _notebooks;

  /// Copies notebook [id]; returns the copy, or null if [id] is unknown.
  Notebook? duplicate(String id, {String? title}) {
    final repo = _notebooks;
    final source = repo.get(id);
    if (source == null) return null;
    final now = repo.clock.nowMs();
    final copyId = repo.clock.newId();
    final copier = RowCopier(repo.db);
    final stamp = {'updated_at': now, 'device_id': repo.deviceId, 'deleted': 0, 'dirty': 1};
    repo.database.transaction(() {
      copier.copy('notebooks', id, {
        ...stamp,
        'id': copyId,
        'title': title ?? '${source.title} (copy)',
        'created_at': now,
        'edited_at': now,
        'favorite': 0,
        'trashed_at': null,
      });
      // A canvas notebook is its own surface; each page is one too.
      final surfaces = <String, String>{id: copyId};
      for (final page in repo.pages.pagesOf(id)) {
        final pageId = repo.clock.newId();
        copier.copy('pages', page.id, {...stamp, 'id': pageId, 'notebook_id': copyId});
        surfaces[page.id] = pageId;
      }
      surfaces.forEach((from, to) {
        _copyContent(copier, 'strokes', 'stroke_chunks', 'stroke_id', from, to, stamp);
        _copyContent(copier, 'elements', 'element_chunks', 'element_id', from, to, stamp);
      });
    });
    return repo.get(copyId);
  }

  /// Copies the live rows of [table] on surface [from] to surface [to],
  /// with their [chunks] index entries (keyed by [idColumn]). All names are
  /// trusted constants.
  void _copyContent(
    RowCopier copier,
    String table,
    String chunks,
    String idColumn,
    String from,
    String to,
    Map<String, Object?> stamp,
  ) {
    final repo = _notebooks;
    final ids = repo.db
        .select('SELECT id FROM $table WHERE surface_id = ? AND deleted = 0', [from])
        .map((r) => r['id'] as String)
        .toList();
    for (final id in ids) {
      final newId = repo.clock.newId();
      copier.copy(table, id, {...stamp, 'id': newId, 'surface_id': to});
      repo.db.execute(
        'INSERT OR IGNORE INTO $chunks (surface_id, cx, cy, $idColumn) '
        'SELECT ?, cx, cy, ? FROM $chunks WHERE $idColumn = ?',
        [to, newId, id],
      );
    }
  }
}
