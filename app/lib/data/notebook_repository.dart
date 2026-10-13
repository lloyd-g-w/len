import 'dart:convert';

import 'package:sqlite3/common.dart';

import '../domain/notebook.dart';
import '../domain/paper.dart';
import 'element_repository.dart';
import 'notebook_duplicator.dart';
import 'notebook_rows.dart';
import 'outline_repository.dart';
import 'page_repository.dart';
import 'recording_repository.dart';
import 'stroke_repository.dart';
import 'syncable.dart';
import 'syncable_table.dart';

/// Persists notebooks and orchestrates notebook-level operations that span
/// pages and strokes (creation with a first page, duplication, trash and
/// cascading deletion).
class NotebookRepository extends SyncableTable {
  NotebookRepository(
    super.database, {
    required super.deviceId,
    required this.pages,
    required this.strokes,
    this.elements,
    this.recordings,
    this.outline,
    super.clock,
  });

  final PageRepository pages;
  final StrokeRepository strokes;

  /// Elements are tombstoned with their surfaces when set.
  final ElementRepository? elements;

  /// Audio recordings are tombstoned with their notebook when set.
  final RecordingRepository? recordings;

  /// The notebook's own outline is deleted and duplicated with it when set.
  final OutlineRepository? outline;

  @override
  String get collection => 'notebooks';

  @override
  String get table => 'notebooks';

  /// Live notebooks that are not in the trash, most recently edited first.
  List<Notebook> list() => db
      .select(
        'SELECT * FROM notebooks WHERE deleted = 0 AND trashed_at IS NULL '
        'ORDER BY edited_at DESC, id',
      )
      .map(NotebookRows.fromRow)
      .toList();

  /// Notebooks in the trash, most recently trashed first.
  List<Notebook> trashed() => db
      .select(
        'SELECT * FROM notebooks WHERE deleted = 0 AND trashed_at IS NOT NULL '
        'ORDER BY trashed_at DESC, id',
      )
      .map(NotebookRows.fromRow)
      .toList();

  /// A live notebook (trashed or not), or null if unknown or deleted.
  Notebook? get(String id) {
    final rows = db.select('SELECT * FROM notebooks WHERE id = ? AND deleted = 0', [id]);
    return rows.isEmpty ? null : NotebookRows.fromRow(rows.first);
  }

  /// Creates a notebook; paged notebooks start with one page, made from
  /// [firstPage] (default: an A4 page of [paper]) — or with one page per
  /// entry of [papers] (e.g. a generated planner), sized and coloured like
  /// [firstPage]. [paper] must be a style without parameters (the notebook's
  /// default for new pages and canvas background).
  Notebook create({
    required String title,
    required NotebookKind kind,
    required PaperStyle paper,
    PaperLook look = PaperLook.standard,
    required int coverColor,
    PaperColor paperColor = PaperColor.white,
    String? folderId,
    PageTemplate? firstPage,
    List<Paper> papers = const [],
  }) {
    assert(!paper.needsParams, 'A notebook default paper has no parameters');
    final now = clock.nowMs();
    final notebook = Notebook(
      id: clock.newId(),
      title: title,
      kind: kind,
      paper: Paper(paper, look: look),
      paperColor: paperColor,
      coverColor: coverColor,
      folderId: folderId,
      createdAt: now,
      updatedAt: now,
    );
    database.transaction(() {
      _write(notebook, deviceId: deviceId, dirty: true);
      if (kind == NotebookKind.paged) {
        final first = firstPage ?? PageTemplate(paper: notebook.paper, color: paperColor);
        if (papers.isEmpty) {
          pages.addPage(notebook.id, template: first);
        } else {
          pages.insertPages(notebook.id, [
            for (final p in papers) specOf(first.copyWith(paper: p)),
          ]);
        }
      }
    });
    return notebook;
  }

  /// Saves metadata changes (title, cover, paper, organisation) and bumps
  /// `updatedAt`.
  Notebook update(Notebook notebook) {
    final updated = notebook.copyWith(updatedAt: nextVersion(notebook.id));
    _write(updated, deviceId: deviceId, dirty: true);
    return updated;
  }

  /// Marks the notebook as recently edited (sorts it to the top).
  void touch(String id) => _change(id, (n) => n.copyWith(editedAt: clock.nowMs()));

  /// Stars or unstars a notebook.
  void setFavorite(String id, bool favorite) => _change(id, (n) => n.copyWith(favorite: favorite));

  /// Moves a notebook into [folderId] (null = library root).
  void moveTo(String id, String? folderId) => _change(id, (n) => n.copyWith(folderId: folderId));

  /// Moves a notebook to the trash; it can be restored until deleted forever.
  void trash(String id) => _change(id, (n) => n.copyWith(trashedAt: clock.nowMs()));

  /// Takes a notebook out of the trash. If its folder no longer exists it
  /// returns to the library root.
  void restore(String id) => _change(id, (n) {
    final folder = n.folderId;
    final folderAlive =
        folder != null &&
        db.select('SELECT 1 FROM folders WHERE id = ? AND deleted = 0', [folder]).isNotEmpty;
    return n.copyWith(trashedAt: null, folderId: folderAlive ? folder : null);
  });

  /// Moves every notebook inside [folderIds] to the trash (folder deletion).
  void trashAllIn(Set<String> folderIds) {
    if (folderIds.isEmpty) return;
    database.transaction(() {
      for (final n in list()) {
        if (folderIds.contains(n.folderId)) trash(n.id);
      }
    });
  }

  /// How long a notebook stays in the trash before [purgeTrash] deletes it
  /// forever (as long as sync keeps tombstones).
  static const trashKeptFor = Duration(days: 30);

  /// Deletes forever the notebooks trashed more than [trashKeptFor] ago;
  /// returns how many.
  int purgeTrash() {
    final before = clock.nowMs() - trashKeptFor.inMilliseconds;
    final expired = [
      for (final n in trashed())
        if (n.trashedAt! < before) n.id,
    ];
    if (expired.isEmpty) return 0;
    database.transaction(() {
      for (final id in expired) {
        delete(id);
      }
    });
    return expired.length;
  }

  /// Permanently deletes every notebook in the trash.
  void emptyTrash() {
    database.transaction(() {
      for (final n in trashed()) {
        delete(n.id);
      }
    });
  }

  /// Copies a notebook with all its pages and strokes under new ids.
  /// Returns the copy, or null if [id] is unknown.
  Notebook? duplicate(String id, {String? title}) =>
      NotebookDuplicator(this).duplicate(id, title: title);

  /// Permanently tombstones the notebook together with its pages, strokes,
  /// elements, recordings and outline, all at one version: every device can
  /// then tell this deletion's tombstones from earlier ones, and bring them
  /// back if the deletion raced an edit (`DeletionConflicts`).
  void delete(String id) {
    database.transaction(() {
      final pageIds = [for (final p in pages.pagesOf(id)) p.id];
      // A canvas notebook is itself a surface; pages are surfaces too.
      final surfaces = [id, ...pageIds];
      final onSurfaces = 'surface_id IN (${List.filled(surfaces.length, '?').join(',')})';
      final version = _batchVersion([
        latestVersion('id = ?', [id]),
        pages.latestVersion('notebook_id = ?', [id]),
        strokes.latestVersion(onSurfaces, surfaces),
        ?elements?.latestVersion(onSurfaces, surfaces),
        ?recordings?.latestVersion('notebook_id = ?', [id]),
        ?outline?.latestVersion('notebook_id = ?', [id]),
      ]);
      db.execute(
        'UPDATE notebooks SET deleted = 1, dirty = 1, updated_at = ?, device_id = ? '
        'WHERE id = ?',
        [version, deviceId, id],
      );
      pages.deleteAllOf(id, version: version);
      strokes.deleteSurfaces(surfaces, version: version);
      elements?.deleteSurfaces(surfaces, version: version);
      recordings?.deleteAllOf(id, version: version);
      outline?.deleteAllOf(id, version: version);
    });
  }

  /// Tombstones page [pageId] with its strokes and elements, all at one
  /// version (like [delete]).
  void deletePage(String pageId) {
    database.transaction(() {
      final version = _batchVersion([
        pages.latestVersion('id = ?', [pageId]),
        strokes.latestVersion('surface_id = ?', [pageId]),
        ?elements?.latestVersion('surface_id = ?', [pageId]),
      ]);
      strokes.deleteSurfaces([pageId], version: version);
      elements?.deleteSurfaces([pageId], version: version);
      pages.delete(pageId, version: version);
    });
  }

  /// A version for writes replacing rows whose newest version is the
  /// largest of [latest]: now, but later than all of them.
  int _batchVersion(List<int> latest) {
    final now = clock.nowMs();
    final newest = latest.fold(0, (a, b) => a > b ? a : b);
    return now > newest ? now : newest + 1;
  }

  void _change(String id, Notebook Function(Notebook) change) {
    final notebook = get(id);
    if (notebook != null) update(change(notebook));
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
      data: deleted ? null : NotebookRows.recordData(row),
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
    _write(NotebookRows.fromRecord(record), deviceId: record.deviceId, dirty: false);
  }

  void _write(Notebook n, {required String deviceId, required bool dirty}) {
    db.execute(
      '''
      INSERT OR REPLACE INTO notebooks (id, title, kind, paper, cover_color,
                                        created_at, updated_at, device_id,
                                        deleted, dirty, folder_id, favorite,
                                        trashed_at, edited_at,
                                        paper_color, paper_data)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?)''',
      [
        n.id,
        n.title,
        n.kind.name,
        n.paper.style.name,
        n.coverColor,
        n.createdAt,
        n.updatedAt,
        deviceId,
        dirty ? 1 : 0,
        n.folderId,
        n.favorite ? 1 : 0,
        n.trashedAt,
        n.editedAt,
        n.paperColor.name,
        jsonEncode(n.paper.toData()),
      ],
    );
  }
}
