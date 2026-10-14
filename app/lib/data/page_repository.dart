import 'dart:convert';
import 'dart:ui';

import 'package:sqlite3/common.dart';

import '../domain/notebook_page.dart';
import '../domain/paper.dart';
import 'page_order.dart';
import 'record_fields.dart';
import 'syncable.dart';
import 'syncable_table.dart';

/// What a new page looks like.
typedef PageSpec = ({Size size, Paper paper, PaperColor color, PageBackground? background});

/// A [PageSpec] for a blank page made from [template].
PageSpec specOf(PageTemplate template) =>
    (size: template.size, paper: template.paper, color: template.color, background: null);

/// Persists the pages of paged notebooks. Local edits only update the
/// columns they change.
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

  /// Adds a blank page after [after] (at the end when null). Uses [template], or an A4 page of [paper] (blank for
  /// styles that need parameters).
  NotebookPage addPage(
    String notebookId, {
    Paper? paper,
    PageTemplate? template,
    NotebookPage? after,
  }) {
    final t =
        template ??
        PageTemplate(paper: paper == null || paper.style.needsParams ? Paper.blank : paper);
    return insertPages(notebookId, [specOf(t)], after: after).single;
  }

  /// Inserts pages in order after [after] (at the end when null) in one
  /// transaction.
  List<NotebookPage> insertPages(String notebookId, List<PageSpec> specs, {NotebookPage? after}) {
    return database.transaction(() {
      var keys = _keysFor(notebookId, specs.length, after: after);
      if (keys == null) {
        _renumber(notebookId);
        keys = _keysFor(notebookId, specs.length, after: after)!;
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

  /// Keys for [count] pages after [after] (found by id, as its sort key may
  /// be stale: renumbered, or moved by a sync), at the end when null or
  /// gone.
  List<double>? _keysFor(String notebookId, int count, {NotebookPage? after}) {
    final pages = pagesOf(notebookId);
    final keys = [for (final p in pages) p.sortKey];
    final index = after == null ? -1 : pages.indexWhere((p) => p.id == after.id);
    if (index == -1) return PageOrder.spread(keys.isEmpty ? null : keys.last, null, count);
    return PageOrder.spread(keys[index], index + 1 < keys.length ? keys[index + 1] : null, count);
  }

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
  void setPaper(Iterable<String> pageIds, {Paper? paper, PaperColor? color}) {
    database.transaction(() {
      for (final id in pageIds) {
        if (paper != null) {
          _update(id, 'paper = ?, paper_data = ?', [paper.style.name, jsonEncode(paper.toData())]);
        }
        if (color != null) _update(id, 'paper_color = ?', [color.name]);
      }
    });
  }

  /// Points the pages of [notebookId] whose background is a page of PDF
  /// [from] at the same page of PDF [to] (relinking a PDF that went
  /// missing). Returns the pages changed.
  List<String> relinkBackground(String notebookId, {required String from, required String to}) {
    final changed = <String>[];
    database.transaction(() {
      for (final page in pagesOf(notebookId)) {
        final bg = page.pdf;
        if (bg == null || bg.blob != from) continue;
        final relinked = PageBackground.pdf(blob: to, pageIndex: bg.pageIndex);
        _update(page.id, 'background = ?', [jsonEncode(relinked.toJson())]);
        changed.add(page.id);
      }
    });
    return changed;
  }

  void setBookmarked(String pageId, bool bookmarked) =>
      _update(pageId, 'bookmarked = ?', [bookmarked ? 1 : 0]);

  /// Tombstones one page, at [version] if given. Its strokes are the
  /// caller's business (see `NotebookRepository.deletePage`).
  void delete(String pageId, {int? version}) =>
      _update(pageId, 'deleted = 1', const [], version: version);

  /// Revives a page deleted with [delete] (undo).
  void restore(String pageId) => _update(pageId, 'deleted = 0', const []);

  /// Tombstones all pages of [notebookId], at [version] if given; returns
  /// their ids.
  List<String> deleteAllOf(String notebookId, {int? version}) {
    final ids = pagesOf(notebookId).map((p) => p.id).toList();
    database.transaction(() {
      for (final id in ids) {
        delete(id, version: version);
      }
    });
    return ids;
  }

  /// Notebook id of a stored page, if known.
  String? notebookOf(String pageId) {
    final rows = database.select('SELECT notebook_id FROM pages WHERE id = ?', [pageId]);
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
  void _update(String id, String assignments, List<Object?> args, {int? version}) {
    db.execute(
      'UPDATE pages SET $assignments, dirty = 1, updated_at = ?, device_id = ? WHERE id = ?',
      [...args, version ?? nextVersion(id), deviceId, id],
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
              'paperData': jsonDecode(row['paper_data'] as String),
              'paperColor': row['paper_color'],
              'bookmarked': row['bookmarked'] == 1,
              'background': background == null ? null : jsonDecode(background),
            },
    );
  }

  @override
  void writeRemote(SyncRecord record) {
    if (record.deleted) {
      database.execute(
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
    final f = RecordFields(record);
    final width = f.number('width');
    final height = f.number('height');
    if (width <= 0) f.invalid('width');
    if (height <= 0) f.invalid('height');
    final rawBackground = f.objectOrNull('background');
    final background = rawBackground == null ? null : PageBackground.fromJson(rawBackground);
    if (rawBackground != null && background == null) f.invalid('background');
    final paper =
        Paper.fromData(f.choice('paper', PaperStyle.values), f.object('paperData')) ??
        f.invalid('paperData');
    _insert(
      NotebookPage(
        id: record.id,
        notebookId: f.string('notebookId'),
        sortKey: f.number('sortKey'),
        width: width,
        height: height,
        paper: paper,
        paperColor: PaperColor.tryParse(f.string('paperColor')) ?? f.invalid('paperColor'),
        bookmarked: f.boolean('bookmarked'),
        background: background,
      ),
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
  }) {
    final background = page.background;
    database.execute(
      '''
      INSERT OR REPLACE INTO pages (id, notebook_id, sort_key, width, height, paper,
                                    paper_data, paper_color, bookmarked, background,
                                    updated_at, device_id, deleted, dirty)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)''',
      [
        page.id,
        page.notebookId,
        page.sortKey,
        page.width,
        page.height,
        page.paper.style.name,
        jsonEncode(page.paper.toData()),
        page.paperColor.name,
        page.bookmarked ? 1 : 0,
        background == null ? null : jsonEncode(background.toJson()),
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

  static Paper _decodePaper(String style, String data) {
    try {
      final json = jsonDecode(data);
      if (json is Map<String, Object?>) {
        return Paper.fromData(PaperStyle.parse(style), json, requireLook: false) ?? Paper.blank;
      }
    } on FormatException {
      // Corrupt local data reads as blank paper.
    }
    return Paper.blank;
  }

  static NotebookPage _rowToPage(Row row) => NotebookPage(
    id: row['id'] as String,
    notebookId: row['notebook_id'] as String,
    sortKey: (row['sort_key'] as num).toDouble(),
    width: (row['width'] as num).toDouble(),
    height: (row['height'] as num).toDouble(),
    paper: _decodePaper(row['paper'] as String, row['paper_data'] as String),
    paperColor: PaperColor.parse(row['paper_color'] as String?),
    bookmarked: row['bookmarked'] == 1,
    background: _decodeBackground(row['background'] as String?),
  );
}
