import 'dart:convert';

import '../domain/chunk_digest.dart';
import '../domain/link_target.dart';
import '../domain/notebook.dart';
import '../domain/recording.dart';
import '../domain/shape_ids.dart';
import '../domain/surface_element.dart';
import '../domain/text/text_data.dart';
import 'notebook_repository.dart';
import 'page_order.dart';
import 'row_copier.dart';
import 'shape_renames.dart';
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
      final elements = _copySurfaces(copier, surfaces, stamp);
      _rechain(surfaces.values, elements);
      _relink(id, copyId, surfaces);
      _copyRecordings(copier, id, copyId, stamp);
      repo.outline?.copyAll(id, copyId, surfaces);
    });
    return repo.get(copyId);
  }

  /// Copies pages [pageIds] of notebook [from] (in that order) to the end
  /// of notebook [to] (UX_AUDIT R7-9): each page with its paper and
  /// background, its strokes and elements (links among the copied pages
  /// lead to the copies), its outline entries, and the recordings its ink
  /// was written during (unless [to] has them already), so it replays
  /// there too. Returns what was made, for [removeCopies].
  CopiedPages copyPages(String from, List<String> pageIds, String to) {
    final repo = _notebooks;
    final now = repo.clock.nowMs();
    final copier = RowCopier(repo.db);
    final stamp = {'updated_at': now, 'device_id': repo.deviceId, 'deleted': 0, 'dirty': 1};
    return repo.database.transaction(() {
      final live = {for (final p in repo.pages.pagesOf(from)) p.id: p};
      final pages = [for (final id in pageIds) ?live[id]];
      final last = repo.pages.pagesOf(to).lastOrNull?.sortKey;
      final keys = PageOrder.spread(last, null, pages.length)!;
      final surfaces = <String, String>{};
      for (final (i, page) in pages.indexed) {
        final pageId = repo.clock.newId();
        copier.copy('pages', page.id, {
          ...stamp,
          'id': pageId,
          'notebook_id': to,
          'sort_key': keys[i],
        });
        surfaces[page.id] = pageId;
      }
      final elements = _copySurfaces(copier, surfaces, stamp);
      _rechain(surfaces.values, elements);
      _relink(from, to, surfaces);
      final outline = repo.outline?.copyAll(from, to, surfaces, onlyPages: true) ?? const [];
      return CopiedPages(
        copies: surfaces,
        outline: outline,
        recordings: _copyRecordingsOf(copier, from, to, surfaces.values, stamp),
      );
    });
  }

  /// Takes back [copyPages]: the copied pages with their content, outline
  /// entries and recordings.
  void removeCopies(CopiedPages copied) {
    final repo = _notebooks;
    repo.database.transaction(() {
      for (final id in copied.pages) {
        repo.deletePage(id);
      }
      for (final id in copied.outline) {
        repo.outline?.delete(id);
      }
      repo.recordings?.deleteAll(copied.recordings);
    });
  }

  /// Copies the strokes and elements of each surface of [surfaces] (old id
  /// → copy's id) to its copy, the copies' shapes renamed ([ShapeIds]):
  /// connectors attach to the copies of their targets. Returns the copied
  /// elements' ids (old → new).
  Map<String, String> _copySurfaces(
    RowCopier copier,
    Map<String, String> surfaces,
    Map<String, Object?> stamp,
  ) {
    final strokes = <String, String>{}, elements = <String, String>{};
    surfaces.forEach((from, to) {
      strokes.addAll(
        _copyContent(copier, 'strokes', 'stroke_chunks', 'stroke_id', from, to, stamp),
      );
      elements.addAll(
        _copyContent(copier, 'elements', 'element_chunks', 'element_id', from, to, stamp),
      );
    });
    final idOf = ShapeIds.mapper(strokes, _notebooks.clock.newId);
    for (final to in surfaces.values) {
      ShapeRenames.apply(_notebooks.db, idOf, surfaceId: to);
    }
    return elements;
  }

  /// Copies the recordings of notebook [from] during which the ink on
  /// [surfaces] (of notebook [to]) was written, except those [to] has
  /// already (the same audio from the same moment); returns the copies.
  List<String> _copyRecordingsOf(
    RowCopier copier,
    String from,
    String to,
    Iterable<String> surfaces,
    Map<String, Object?> stamp,
  ) {
    final repo = _notebooks;
    final recordings = repo.recordings;
    if (recordings == null || surfaces.isEmpty) return const [];
    final marks = List.filled(surfaces.length, '?').join(', ');
    final times = [
      for (final table in ['strokes', 'elements'])
        for (final r in repo.db.select(
          'SELECT created_at FROM $table WHERE surface_id IN ($marks) AND deleted = 0',
          surfaces.toList(),
        ))
          r['created_at'] as int,
    ];
    String key(Recording r) => '${r.startedAt}:${r.blobs.join(',')}';
    final there = {for (final r in recordings.listOf(to)) key(r)};
    return [
      for (final r in recordings.listOf(from))
        if (!there.contains(key(r)) && times.any((t) => r.inkPositionOf(t) != null))
          _copyRecording(copier, r.id, to, stamp),
    ];
  }

  String _copyRecording(RowCopier copier, String id, String to, Map<String, Object?> stamp) {
    final copy = _notebooks.clock.newId();
    copier.copy('recordings', id, {...stamp, 'id': copy, 'notebook_id': to});
    return copy;
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
        final element = StrokeQueries.rowToElement(
          db.select('SELECT * FROM elements WHERE id = ?', [row['id']]).first,
        );
        if (element == null) continue;
        db.execute('UPDATE element_chunks SET digest = ? WHERE element_id = ?', [
          ChunkDigest.ofElement(element),
          row['id'],
        ]);
      }
    }
  }

  /// Text boxes flowing across the copied pages continue the copies of
  /// the boxes they continued ([elements]: old id → copy's id); one whose
  /// box before was not copied stands alone.
  void _rechain(Iterable<String> surfaces, Map<String, String> elements) {
    final db = _notebooks.db;
    for (final copied in surfaces) {
      final rows = db.select(
        'SELECT id, data FROM elements WHERE surface_id = ? AND type = ? AND deleted = 0 '
        "AND data LIKE '%\"flow\"%'",
        [copied, ElementType.text.name],
      );
      for (final row in rows) {
        final data = StrokeQueries.decodeElementData(row['data'] as String);
        final flow = TextFlow.fromJson(data?['flow']);
        if (data == null || flow == null) continue;
        final from = elements[flow.from];
        final next = {...data}..remove('flow');
        if (from != null) {
          next['flow'] = flow.withFrom(from).toJson();
        }
        db.execute('UPDATE elements SET data = ? WHERE id = ?', [jsonEncode(next), row['id']]);
        final element = StrokeQueries.rowToElement(
          db.select('SELECT * FROM elements WHERE id = ?', [row['id']]).first,
        );
        if (element == null) continue;
        db.execute('UPDATE element_chunks SET digest = ? WHERE element_id = ?', [
          ChunkDigest.ofElement(element),
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
      _copyRecording(copier, id, to, stamp);
    }
  }

  /// Copies the live rows of [table] on surface [from] to surface [to],
  /// with their [chunks] index entries (keyed by [idColumn]). All names are
  /// trusted constants.
  Map<String, String> _copyContent(
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
    final copies = <String, String>{};
    for (final id in ids) {
      final newId = repo.clock.newId();
      copier.copy(table, id, {...stamp, 'id': newId, 'surface_id': to});
      // A stroke's digest is its id's hash; an element's, its value's.
      repo.db.execute(
        'INSERT OR IGNORE INTO $chunks (surface_id, cx, cy, $idColumn, digest) '
        'SELECT ?, cx, cy, ?, COALESCE(?, digest) FROM $chunks WHERE $idColumn = ?',
        [to, newId, table == 'strokes' ? ChunkDigest.ofStroke(newId) : null, id],
      );
      copies[id] = newId;
    }
    return copies;
  }
}

/// What [NotebookDuplicator.copyPages] made: page, outline entry and
/// recording ids.
class CopiedPages {
  const CopiedPages({required this.copies, required this.outline, required this.recordings});

  /// Each copied page's id → its copy's, in page order.
  final Map<String, String> copies;

  /// The copies' ids, in page order.
  List<String> get pages => copies.values.toList();

  final List<String> outline;
  final List<String> recordings;
}
