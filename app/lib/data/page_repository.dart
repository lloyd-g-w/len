import 'package:sqlite3/sqlite3.dart';

import '../domain/notebook_page.dart';
import '../domain/paper.dart';
import 'syncable.dart';
import 'syncable_table.dart';

/// Persists the pages of paged notebooks.
class PageRepository extends SyncableTable {
  PageRepository(super.database, {required super.deviceId, super.clock});

  @override
  String get collection => 'pages';

  @override
  String get table => 'pages';

  /// Live pages of [notebookId] in display order.
  List<NotebookPage> pagesOf(String notebookId) => db
      .select(
        'SELECT * FROM pages WHERE notebook_id = ? AND deleted = 0 '
        'ORDER BY sort_key, id',
        [notebookId],
      )
      .map(_rowToPage)
      .toList();

  /// Appends a page after [after] (or at the end when null).
  NotebookPage addPage(
    String notebookId, {
    required PaperStyle paper,
    NotebookPage? after,
  }) {
    final pages = pagesOf(notebookId);
    final page = NotebookPage(
      id: clock.newId(),
      notebookId: notebookId,
      sortKey: _sortKeyAfter(pages, after),
      width: PageSize.a4Width,
      height: PageSize.a4Height,
      paper: paper,
    );
    _write(page, updatedAt: clock.nowMs(), deviceId: deviceId, dirty: true);
    return page;
  }

  /// Tombstones all pages of [notebookId]; returns their ids.
  List<String> deleteAllOf(String notebookId) {
    final ids = pagesOf(notebookId).map((p) => p.id).toList();
    final now = clock.nowMs();
    database.transaction(() {
      for (final id in ids) {
        db.execute(
          'UPDATE pages SET deleted = 1, dirty = 1, updated_at = ?, device_id = ? '
          'WHERE id = ?',
          [nextVersion(id, now), deviceId, id],
        );
      }
    });
    return ids;
  }

  /// Notebook id of a stored page, if known.
  String? notebookOf(String pageId) {
    final rows = db.select('SELECT notebook_id FROM pages WHERE id = ?', [pageId]);
    return rows.isEmpty ? null : rows.first['notebook_id'] as String;
  }

  static double _sortKeyAfter(List<NotebookPage> pages, NotebookPage? after) {
    if (pages.isEmpty) return 1;
    final index = after == null ? -1 : pages.indexWhere((p) => p.id == after.id);
    if (index == -1 || index == pages.length - 1) return pages.last.sortKey + 1;
    return (pages[index].sortKey + pages[index + 1].sortKey) / 2;
  }

  // ---------------------------------------------------------------------------
  // Sync

  @override
  SyncRecord rowToRecord(Row row) {
    final deleted = row['deleted'] == 1;
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
    _write(
      NotebookPage(
        id: record.id,
        notebookId: notebookId,
        sortKey: sortKey.toDouble(),
        width: width.toDouble(),
        height: height.toDouble(),
        paper: PaperStyle.parse(paper),
      ),
      updatedAt: record.updatedAt,
      deviceId: record.deviceId,
      dirty: false,
    );
  }

  void _write(
    NotebookPage page, {
    required int updatedAt,
    required String deviceId,
    required bool dirty,
  }) {
    db.execute(
      '''
      INSERT OR REPLACE INTO pages (id, notebook_id, sort_key, width, height,
                                    paper, updated_at, device_id, deleted, dirty)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?)''',
      [
        page.id,
        page.notebookId,
        page.sortKey,
        page.width,
        page.height,
        page.paper.name,
        updatedAt,
        deviceId,
        dirty ? 1 : 0,
      ],
    );
  }

  static NotebookPage _rowToPage(Row row) => NotebookPage(
        id: row['id'] as String,
        notebookId: row['notebook_id'] as String,
        sortKey: (row['sort_key'] as num).toDouble(),
        width: (row['width'] as num).toDouble(),
        height: (row['height'] as num).toDouble(),
        paper: PaperStyle.parse(row['paper'] as String),
      );
}
