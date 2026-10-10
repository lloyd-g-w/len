import 'dart:ui';

import 'package:sqlite3/sqlite3.dart';

import '../app_database.dart';
import 'search_query.dart';
import 'search_schema.dart';

/// What a [SearchHit] matched.
enum SearchHitKind {
  /// A notebook's title.
  notebookTitle,

  /// A folder's name.
  folderName,

  /// A text box on a page or canvas.
  text,

  /// The text of an imported PDF page.
  pdf;

  static SearchHitKind of(String kind) => switch (kind) {
    SearchSchema.notebook => notebookTitle,
    SearchSchema.folder => folderName,
    SearchSchema.pdf => pdf,
    _ => text,
  };
}

/// One indexed document matching a query.
class SearchHit {
  const SearchHit({
    required this.kind,
    required this.refId,
    required this.body,
    required this.rank,
    this.notebookId,
    this.surfaceId,
    this.pageIndex,
  });

  final SearchHitKind kind;

  /// The notebook, folder, element or page id the hit is about.
  final String refId;

  /// The full indexed text.
  final String body;

  /// Relevance; lower is better (FTS5 bm25, or 0 without FTS5).
  final double rank;

  /// The notebook the hit is in (null for folders).
  final String? notebookId;

  /// The page or canvas the content is on (text and PDF hits).
  final String? surfaceId;

  /// Zero-based page number in a paged notebook (null on canvases and for
  /// titles).
  final int? pageIndex;

  bool get isContent => kind == SearchHitKind.text || kind == SearchHitKind.pdf;

  @override
  String toString() => 'SearchHit(${kind.name} $refId p$pageIndex "$body")';
}

/// Queries the local full-text index (see [SearchSchema]).
///
/// Writes need no calls here: triggers keep the index current. Hits in
/// trashed or deleted notebooks, and on deleted pages, are left out.
class SearchIndex {
  /// Queries [database]; [preferFts] false forces the `LIKE` fallback
  /// (tests).
  SearchIndex(this.database, {bool preferFts = true}) {
    // A database migrated by a build without FTS5 gets the index as soon
    // as one with FTS5 opens it.
    _fts = SearchSchema.ensureFts(db) && preferFts;
  }

  final AppDatabase database;
  late final bool _fts;

  Database get db => database.db;

  /// Whether queries use FTS5 (else `LIKE`, slower and accent-sensitive).
  bool get usesFts => _fts;

  /// Content and title hits for [query], at most [limit], best first —
  /// or, with [notebookId], only that notebook's content in page order.
  List<SearchHit> search(SearchQuery query, {String? notebookId, int limit = 300}) {
    if (query.isEmpty) return const [];
    final (from, where, args) = _matchClause(query);
    final rows = db.select(
      '''
      SELECT d.kind, d.ref_id, d.surface_id, d.body, ${_fts ? 'bm25(search_fts)' : '0'} AS rank,
             n.id AS notebook_id, p.id AS page_id,
             (SELECT COUNT(*) FROM pages q
              WHERE q.notebook_id = p.notebook_id AND q.deleted = 0
                AND (q.sort_key < p.sort_key OR (q.sort_key = p.sort_key AND q.id < p.id)))
               AS page_index
      FROM $from
      LEFT JOIN pages p ON d.kind IN ('${SearchSchema.text}', '${SearchSchema.pdf}')
                        AND p.id = d.surface_id
      JOIN notebooks n ON n.id = CASE WHEN d.kind = '${SearchSchema.notebook}' THEN d.ref_id
                                      ELSE coalesce(p.notebook_id, d.surface_id) END
      WHERE $where AND n.deleted = 0 AND n.trashed_at IS NULL AND (p.id IS NULL OR p.deleted = 0)
        ${notebookId == null ? '' : "AND n.id = ? AND d.kind <> '${SearchSchema.notebook}'"}
      ORDER BY ${notebookId == null ? 'rank' : 'page_index'}, d.id
      LIMIT ?''',
      [...args, ?notebookId, limit],
    );
    return [
      for (final r in rows)
        if (_fts || query.matches(r['body'] as String))
          SearchHit(
            kind: SearchHitKind.of(r['kind'] as String),
            refId: r['ref_id'] as String,
            body: r['body'] as String,
            rank: (r['rank'] as num).toDouble(),
            notebookId: r['notebook_id'] as String,
            surfaceId: r['kind'] == SearchSchema.notebook ? null : r['surface_id'] as String,
            pageIndex: r['page_id'] == null ? null : r['page_index'] as int,
          ),
    ];
  }

  /// Folders whose names match [query] (live ones only).
  List<SearchHit> searchFolders(SearchQuery query, {int limit = 50}) {
    if (query.isEmpty) return const [];
    final (from, where, args) = _matchClause(query);
    final rows = db.select(
      '''
      SELECT d.ref_id, d.body, ${_fts ? 'bm25(search_fts)' : '0'} AS rank
      FROM $from JOIN folders f ON f.id = d.ref_id AND f.deleted = 0
      WHERE $where AND d.kind = '${SearchSchema.folder}'
      ORDER BY rank LIMIT ?''',
      [...args, limit],
    );
    return [
      for (final r in rows)
        if (_fts || query.matches(r['body'] as String))
          SearchHit(
            kind: SearchHitKind.folderName,
            refId: r['ref_id'] as String,
            body: r['body'] as String,
            rank: (r['rank'] as num).toDouble(),
          ),
    ];
  }

  /// The FROM clause (aliasing the documents as `d`), the match condition
  /// and its arguments.
  (String, String, List<Object?>) _matchClause(SearchQuery query) {
    if (_fts) {
      return (
        'search_fts JOIN search_docs d ON d.id = search_fts.rowid',
        'search_fts MATCH ?',
        [query.ftsExpression],
      );
    }
    final likes = query.likePatterns;
    final where = [for (final _ in likes) r"d.body LIKE ? ESCAPE '\'"].join(' AND ');
    return ('search_docs d', '($where)', likes);
  }

  /// The box (unrotated rect and rotation about its centre) of live
  /// element [id], for highlighting a text box hit.
  ({Rect rect, double rotation})? elementBox(String id) {
    final rows = db.select(
      'SELECT x, y, w, h, rotation FROM elements WHERE id = ? AND deleted = 0',
      [id],
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    double d(String c) => (r[c] as num).toDouble();
    return (rect: Rect.fromLTWH(d('x'), d('y'), d('w'), d('h')), rotation: d('rotation'));
  }

  /// Empties and refills the index from the synced tables.
  void rebuild() => database.transaction(() => SearchSchema.rebuild(db));

  /// Number of indexed documents (for diagnostics and tests).
  int get documentCount => db.select('SELECT COUNT(*) AS n FROM search_docs').first['n'] as int;
}
