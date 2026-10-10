import 'dart:convert';
import 'dart:ui';

import 'package:sqlite3/common.dart';

import '../domain/notebook_page.dart';
import '../domain/paper.dart';
import 'page_order.dart';
import 'syncable.dart';
import 'syncable_table.dart';

/// What a new page looks like.
typedef PageSpec = ({Size size, PaperStyle paper, PaperColor color, PageBackground? background});

/// A [PageSpec] for a blank page made from [template].
PageSpec specOf(PageTemplate template) =>
    (size: template.size, paper: template.style, color: template.color, background: null);

/// Persists the pages of paged notebooks.
///
/// Columns written by remote records keep their raw values (e.g. a paper
/// style or background type from a newer app version), and local edits
/// only update the columns they change, so such values survive a round
/// trip through this device.
class PageRepository extends SyncableTable {
  PageRepository(super.database, {required super.deviceId, super.clock});

  @override
  String get collection => 'pages';

  @override
  String get table => 'pages';

  /// Live pages of [notebookId] in display order.
  List<NotebookPage> pagesOf(String notebookId) => db
      .select('SELECT * FROM pages WHERE notebook_id = ? AND deleted = 0 ORDER BY sort_key, id', [
        notebookId,
      ])
      .map(_rowToPage)
      .toList();

  /// A live page by id.
  NotebookPage? get(String id) {
    final rows = db.select('SELECT * FROM pages WHERE id = ? AND deleted = 0', [id]);
    return rows.isEmpty ? null : _rowToPage(rows.first);
  }

  /// Adds a blank page after [after] (or before [before]; at the end when
  /// both are null). Uses [template], or a blank A4 page of [paper].
  NotebookPage addPage(
    String notebookId, {
    PaperStyle? paper,
    PageTemplate? template,
    NotebookPage? after,
    NotebookPage? before,
  }) {
    final t = template ?? PageTemplate(style: paper ?? PaperStyle.blank);
    return insertPages(notebookId, [specOf(t)], after: after, before: before).single;
  }

  /// Inserts pages in order after [after] / before [before] (at the end when
  /// both are null) in one transaction.
  List<NotebookPage> insertPages(
    String notebookId,
    List<PageSpec> specs, {
    NotebookPage? after,
    NotebookPage? before,
  }) {
    return database.transaction(() {
      var keys = _keysFor(notebookId, specs.length, after: after, before: before);
      if (keys == null) {
        _renumber(notebookId);
        keys = _keysFor(notebookId, specs.length, after: after, before: before)!;
      }
      final now = clock.nowMs();
      final created = <NotebookPage>[];
      for (var i = 0; i < specs.length; i++) {
        final s = specs[i];
        final page = NotebookPage(
          id: clock.newId(),
          notebookId: notebookId,
          sortKey: keys[i],
          width: s.size.width,
          height: s.size.height,
          paper: s.paper,
          paperColor: s.color,
          background: s.background,
        );
        _insert(page, updatedAt: now, deviceId: deviceId, dirty: true);
        created.add(page);
      }
      return created;
    });
  }

  List<double>? _keysFor(
    String notebookId,
    int count, {
    NotebookPage? after,
    NotebookPage? before,
  }) {
    final keys = pagesOf(notebookId).map((p) => p.sortKey).toList();
    final anchor = after ?? before;
    var index = anchor == null ? -1 : _indexOfKey(keys, anchor.sortKey);
    if (index == -1) return PageOrder.spread(keys.isEmpty ? null : keys.last, null, count);
    if (before != null) index--; // Insert between index and index + 1.
    return PageOrder.spread(
      index >= 0 ? keys[index] : null,
      index + 1 < keys.length ? keys[index + 1] : null,
      count,
    );
  }

  static int _indexOfKey(List<double> keys, double key) => keys.indexOf(key);

  /// Moves [page] to position [toIndex] of its notebook.
  void move(NotebookPage page, int toIndex) {
    database.transaction(() {
      var pages = pagesOf(page.notebookId);
      var from = pages.indexWhere((p) => p.id == page.id);
      if (from == -1 || from == toIndex) return;
      var key = PageOrder.forMove([for (final p in pages) p.sortKey], from, toIndex);
      if (key == null) {
        _renumber(page.notebookId);
        pages = pagesOf(page.notebookId);
        from = pages.indexWhere((p) => p.id == page.id);
        key = PageOrder.forMove([for (final p in pages) p.sortKey], from, toIndex)!;
      }
      _update(page.id, 'sort_key = ?', [key]);
    });
  }

  /// Sets the paper of the given pages (the template of existing pages;
  /// their size and background stay).
  void setPaper(Iterable<String> pageIds, {PaperStyle? style, PaperColor? color}) {
    database.transaction(() {
      for (final id in pageIds) {
        if (style != null) _update(id, 'paper = ?', [style.name]);
        if (color != null) _update(id, 'paper_color = ?', [color.name]);
      }
    });
  }

  void setBookmarked(String pageId, bool bookmarked) =>
      _update(pageId, 'bookmarked = ?', [bookmarked ? 1 : 0]);

  /// Tombstones one page. Its strokes are the caller's business.
  void delete(String pageId) => _update(pageId, 'deleted = 1', const []);

  /// Revives a page deleted with [delete] (undo).
  void restore(String pageId) => _update(pageId, 'deleted = 0', const []);

  /// Tombstones all pages of [notebookId]; returns their ids.
  List<String> deleteAllOf(String notebookId) {
    final ids = pagesOf(notebookId).map((p) => p.id).toList();
    database.transaction(() {
      for (final id in ids) {
        delete(id);
      }
    });
    return ids;
  }

  /// Notebook id of a stored page, if known.
  String? notebookOf(String pageId) {
    final rows = db.select('SELECT notebook_id FROM pages WHERE id = ?', [pageId]);
    return rows.isEmpty ? null : rows.first['notebook_id'] as String;
  }

  /// Distinct blobs referenced by live pages' backgrounds.
  Set<String> referencedBlobs() => {
    for (final row in db.select(
      'SELECT background FROM pages WHERE deleted = 0 AND background IS NOT NULL',
    ))
      ?_decodeBackground(row['background'] as String?)?.blob,
  };

  /// Gives every page of [notebookId] an integer key (1, 2, …).
  void _renumber(String notebookId) {
    final pages = pagesOf(notebookId);
    for (var i = 0; i < pages.length; i++) {
      _update(pages[i].id, 'sort_key = ?', [i + 1.0]);
    }
  }

  /// A local edit of some columns: bumps the version and marks it dirty.
  void _update(String id, String assignments, List<Object?> args) {
    db.execute(
      'UPDATE pages SET $assignments, dirty = 1, updated_at = ?, device_id = ? WHERE id = ?',
      [...args, nextVersion(id), deviceId, id],
    );
  }

  // ---------------------------------------------------------------------------
  // Sync

  @override
  SyncRecord rowToRecord(Row row) {
    final deleted = row['deleted'] == 1;
    final background = row['background'] as String?;
    return SyncRecord(
      collection: collection,
      id: row['id'] as String,
      updatedAt: row['updated_at'] as int,
      deviceId: row['device_id'] as String,
      deleted: deleted,
      data: deleted
          ? null
          : {
              'notebookId': row['notebook_id'],
              'sortKey': row['sort_key'],
              'width': row['width'],
              'height': row['height'],
              'paper': row['paper'],
              'paperColor': row['paper_color'],
              'bookmarked': row['bookmarked'] == 1,
              'background': background == null ? null : jsonDecode(background),
            },
    );
  }

  @override
  void writeRemote(SyncRecord record) {
    if (record.deleted) {
      db.execute(
        '''
        INSERT INTO pages (id, notebook_id, sort_key, width, height, paper,
                           updated_at, device_id, deleted, dirty)
        VALUES (?, '', 0, 0, 0, 'blank', ?, ?, 1, 0)
        ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at,
          device_id = excluded.device_id, deleted = 1, dirty = 0''',
        [record.id, record.updatedAt, record.deviceId],
      );
      return;
    }
    final d = record.data!;
    final notebookId = d['notebookId'];
    final sortKey = d['sortKey'];
    final width = d['width'];
    final height = d['height'];
    final paper = d['paper'];
    if (notebookId is! String ||
        sortKey is! num ||
        width is! num ||
        height is! num ||
        paper is! String ||
        width <= 0 ||
        height <= 0) {
      throw FormatException('Malformed page ${record.id}');
    }
    // Optional fields (added later): tolerate odd values, and keep the
    // local row's value when a field is missing (an older client's record),
    // so e.g. a reorder from such a client does not drop a PDF background.
    final local = db.select(
      'SELECT paper_color, bookmarked, background FROM pages WHERE id = ? AND deleted = 0',
      [record.id],
    );
    final old = local.isEmpty ? null : local.first;
    final color = d['paperColor'];
    final background = d['background'];
    _writeRow(
      id: record.id,
      notebookId: notebookId,
      sortKey: sortKey.toDouble(),
      width: width.toDouble(),
      height: height.toDouble(),
      paper: paper,
      paperColor: d.containsKey('paperColor') || old == null
          ? (color is String ? color : PaperColor.white.name)
          : old['paper_color'] as String,
      bookmarked: d.containsKey('bookmarked') || old == null
          ? d['bookmarked'] == true
          : old['bookmarked'] == 1,
      background: d.containsKey('background') || old == null
          ? (background is Map ? jsonEncode(background) : null)
          : old['background'] as String?,
      updatedAt: record.updatedAt,
      deviceId: record.deviceId,
      dirty: false,
    );
  }

  void _insert(
    NotebookPage page, {
    required int updatedAt,
    required String deviceId,
    required bool dirty,
  }) => _writeRow(
    id: page.id,
    notebookId: page.notebookId,
    sortKey: page.sortKey,
    width: page.width,
    height: page.height,
    paper: page.paper.name,
    paperColor: page.paperColor.name,
    bookmarked: page.bookmarked,
    background: page.background == null ? null : jsonEncode(page.background!.toJson()),
    updatedAt: updatedAt,
    deviceId: deviceId,
    dirty: dirty,
  );

  void _writeRow({
    required String id,
    required String notebookId,
    required double sortKey,
    required double width,
    required double height,
    required String paper,
    required String paperColor,
    required bool bookmarked,
    required String? background,
    required int updatedAt,
    required String deviceId,
    required bool dirty,
  }) {
    db.execute(
      '''
      INSERT OR REPLACE INTO pages (id, notebook_id, sort_key, width, height, paper,
                                    paper_color, bookmarked, background,
                                    updated_at, device_id, deleted, dirty)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)''',
      [
        id,
        notebookId,
        sortKey,
        width,
        height,
        paper,
        paperColor,
        bookmarked ? 1 : 0,
        background,
        updatedAt,
        deviceId,
        dirty ? 1 : 0,
      ],
    );
  }

  static PageBackground? _decodeBackground(String? json) {
    if (json == null) return null;
    try {
      return PageBackground.fromJson(jsonDecode(json));
    } on FormatException {
      return null;
    }
  }

  static NotebookPage _rowToPage(Row row) => NotebookPage(
    id: row['id'] as String,
    notebookId: row['notebook_id'] as String,
    sortKey: (row['sort_key'] as num).toDouble(),
    width: (row['width'] as num).toDouble(),
    height: (row['height'] as num).toDouble(),
    paper: PaperStyle.parse(row['paper'] as String),
    paperColor: PaperColor.parse(row['paper_color'] as String?),
    bookmarked: row['bookmarked'] == 1,
    background: _decodeBackground(row['background'] as String?),
  );
}
