import 'dart:convert';

import '../domain/link_target.dart';
import '../domain/notebook.dart';
import '../domain/surface_element.dart';
import 'notebook_repository.dart';
import 'row_copier.dart';
import 'stroke_queries.dart';

/// Deep-copies a notebook: its row, its pages, every live stroke and
/// element (with their chunk indexes) and its audio recordings, all under
/// new ids and marked dirty for sync; links to its own pages lead to the
/// copies.
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
      _relink(id, copyId, surfaces);
      _copyRecordings(copier, id, copyId, stamp);
      repo.outline?.copyAll(id, copyId, surfaces);
    });
    return repo.get(copyId);
  }

  /// Points the copied link elements that lead to a page of notebook
  /// [from] at that page's copy in [to], so the copy's links stay inside
  /// it (links to other notebooks, or to pages since deleted, are kept).
  void _relink(String from, String to, Map<String, String> surfaces) {
    final db = _notebooks.db;
    for (final copied in surfaces.values) {
      final rows = db.select(
        'SELECT id, data FROM elements WHERE surface_id = ? AND type = ? AND deleted = 0',
        [copied, ElementType.link.name],
      );
      for (final row in rows) {
        final data = StrokeQueries.decodeElementData(row['data'] as String);
        final target = LinkTarget.fromJson(data?['target']);
        if (target is! PageLinkTarget || target.notebookId != from) continue;
        final page = surfaces[target.pageId];
        if (page == null) continue;
        final relinked = PageLinkTarget(notebookId: to, pageId: page);
        db.execute('UPDATE elements SET data = ? WHERE id = ?', [
          jsonEncode({...?data, 'target': relinked.toJson()}),
          row['id'],
        ]);
      }
    }
  }

  /// Copies the recordings of notebook [from] to [to]. The audio blobs are
  /// content-addressed, so the copies share them. Strokes keep their
  /// `createdAt`, so the copied ink replays in step with the copies.
  void _copyRecordings(RowCopier copier, String from, String to, Map<String, Object?> stamp) {
    final repo = _notebooks;
    final ids = repo.db
        .select('SELECT id FROM recordings WHERE notebook_id = ? AND deleted = 0', [from])
        .map((r) => r['id'] as String)
        .toList();
    for (final id in ids) {
      copier.copy('recordings', id, {...stamp, 'id': repo.clock.newId(), 'notebook_id': to});
    }
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
