import 'package:sqlite3/sqlite3.dart';

import '../domain/notebook.dart';
import '../domain/paper.dart';
import 'page_repository.dart';
import 'stroke_repository.dart';
import 'syncable.dart';
import 'syncable_table.dart';

/// Persists notebooks and orchestrates notebook-level operations that span
/// pages and strokes (creation with a first page, cascading deletion).
class NotebookRepository extends SyncableTable {
  NotebookRepository(
    super.database, {
    required super.deviceId,
    required this.pages,
    required this.strokes,
    super.clock,
  });

  final PageRepository pages;
  final StrokeRepository strokes;

  @override
  String get collection => 'notebooks';

  @override
  String get table => 'notebooks';

  /// Live notebooks, most recently updated first.
  List<Notebook> list() => db
      .select('SELECT * FROM notebooks WHERE deleted = 0 ORDER BY updated_at DESC')
      .map(_rowToNotebook)
      .toList();

  Notebook? get(String id) {
    final rows = db.select('SELECT * FROM notebooks WHERE id = ? AND deleted = 0', [id]);
    return rows.isEmpty ? null : _rowToNotebook(rows.first);
  }

  /// Creates a notebook; paged notebooks start with one page, made from
  /// [firstPage] (default: a blank A4 page of [paper]).
  Notebook create({
    required String title,
    required NotebookKind kind,
    required PaperStyle paper,
    required int coverColor,
    PageTemplate? firstPage,
  }) {
    final now = clock.nowMs();
    final notebook = Notebook(
      id: clock.newId(),
      title: title,
      kind: kind,
      paper: paper,
      coverColor: coverColor,
      createdAt: now,
      updatedAt: now,
    );
    database.transaction(() {
      _write(notebook, deviceId: deviceId, dirty: true);
      if (kind == NotebookKind.paged) {
        pages.addPage(notebook.id, template: firstPage ?? PageTemplate(style: paper));
      }
    });
    return notebook;
  }

  /// Saves metadata changes (title, cover, paper) and bumps `updatedAt`.
  Notebook update(Notebook notebook) {
    final updated = notebook.copyWith(updatedAt: nextVersion(notebook.id));
    _write(updated, deviceId: deviceId, dirty: true);
    return updated;
  }

  /// Marks the notebook as recently edited (sorts it to the top).
  void touch(String id) {
    final notebook = get(id);
    if (notebook != null) update(notebook);
  }

  /// Tombstones the notebook together with its pages and strokes.
  void delete(String id) {
    database.transaction(() {
      db.execute(
        'UPDATE notebooks SET deleted = 1, dirty = 1, updated_at = ?, device_id = ? '
        'WHERE id = ?',
        [nextVersion(id), deviceId, id],
      );
      final pageIds = pages.deleteAllOf(id);
      // A canvas notebook is itself a surface; pages are surfaces too.
      strokes.deleteSurfaces([id, ...pageIds]);
    });
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
              'title': row['title'],
              'kind': row['kind'],
              'paper': row['paper'],
              'coverColor': row['cover_color'],
              'createdAt': row['created_at'],
            },
    );
  }

  @override
  void writeRemote(SyncRecord record) {
    if (record.deleted) {
      db.execute(
        '''
        INSERT INTO notebooks (id, title, kind, paper, cover_color, created_at,
                               updated_at, device_id, deleted, dirty)
        VALUES (?, '', 'paged', 'blank', 0, 0, ?, ?, 1, 0)
        ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at,
          device_id = excluded.device_id, deleted = 1, dirty = 0''',
        [record.id, record.updatedAt, record.deviceId],
      );
      return;
    }
    final d = record.data!;
    final title = d['title'];
    final kind = d['kind'];
    final paper = d['paper'];
    final coverColor = d['coverColor'];
    final createdAt = d['createdAt'];
    if (title is! String ||
        kind is! String ||
        paper is! String ||
        coverColor is! int ||
        createdAt is! int) {
      throw FormatException('Malformed notebook ${record.id}');
    }
    _write(
      Notebook(
        id: record.id,
        title: title,
        kind: NotebookKind.parse(kind),
        paper: PaperStyle.parse(paper),
        coverColor: coverColor,
        createdAt: createdAt,
        updatedAt: record.updatedAt,
      ),
      deviceId: record.deviceId,
      dirty: false,
    );
  }

  void _write(Notebook n, {required String deviceId, required bool dirty}) {
    db.execute(
      '''
      INSERT OR REPLACE INTO notebooks (id, title, kind, paper, cover_color,
                                        created_at, updated_at, device_id,
                                        deleted, dirty)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?)''',
      [
        n.id,
        n.title,
        n.kind.name,
        n.paper.name,
        n.coverColor,
        n.createdAt,
        n.updatedAt,
        deviceId,
        dirty ? 1 : 0,
      ],
    );
  }

  static Notebook _rowToNotebook(Row row) => Notebook(
        id: row['id'] as String,
        title: row['title'] as String,
        kind: NotebookKind.parse(row['kind'] as String),
        paper: PaperStyle.parse(row['paper'] as String),
        coverColor: row['cover_color'] as int,
        createdAt: row['created_at'] as int,
        updatedAt: row['updated_at'] as int,
      );
}
