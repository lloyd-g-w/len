import 'package:sqlite3/common.dart';

import '../domain/cover_style.dart';
import '../domain/notebook.dart';
import '../domain/paper.dart';
import 'element_repository.dart';
import 'notebook_duplicator.dart';
import 'page_repository.dart';
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
    super.clock,
  });

  final PageRepository pages;
  final StrokeRepository strokes;

  /// Elements are tombstoned with their surfaces when set.
  final ElementRepository? elements;

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
      .map(_rowToNotebook)
      .toList();

  /// Notebooks in the trash, most recently trashed first.
  List<Notebook> trashed() => db
      .select(
        'SELECT * FROM notebooks WHERE deleted = 0 AND trashed_at IS NOT NULL '
        'ORDER BY trashed_at DESC, id',
      )
      .map(_rowToNotebook)
      .toList();

  /// A live notebook (trashed or not), or null if unknown or deleted.
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
    PaperColor paperColor = PaperColor.white,
    CoverStyle coverStyle = CoverStyle.plain,
    String? folderId,
    PageTemplate? firstPage,
  }) {
    final now = clock.nowMs();
    final notebook = Notebook(
      id: clock.newId(),
      title: title,
      kind: kind,
      paper: paper,
      paperColor: paperColor,
      coverColor: coverColor,
      coverStyle: coverStyle,
      folderId: folderId,
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

  /// Permanently tombstones the notebook together with its pages and strokes.
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
      elements?.deleteSurfaces([id, ...pageIds]);
    });
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
      data: deleted
          ? null
          : {
              'title': row['title'],
              'kind': row['kind'],
              'paper': row['paper'],
              'paperColor': row['paper_color'],
              'coverColor': row['cover_color'],
              'coverStyle': row['cover_style'],
              'createdAt': row['created_at'],
              'editedAt': row['edited_at'],
              'folderId': row['folder_id'],
              'favorite': row['favorite'] == 1,
              'trashedAt': row['trashed_at'],
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
    final local = db.select('SELECT * FROM notebooks WHERE id = ? AND deleted = 0', [record.id]);
    final notebook = _notebookFromRecord(
      record,
      local: local.isEmpty ? null : _rowToNotebook(local.first),
    );
    _write(notebook, deviceId: record.deviceId, dirty: false);
  }

  /// Parses a live record. Fields added after protocol v1 (folder, favourite,
  /// trash, cover style, edit time) are optional: a client that predates
  /// them omits them when it edits, e.g., the title. Missing fields keep the
  /// [local] notebook's values (so such an edit does not move, unstar or
  /// restore it), or take their defaults when the notebook is new here.
  static Notebook _notebookFromRecord(SyncRecord record, {Notebook? local}) {
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
    final folderId = d['folderId'];
    final trashedAt = d['trashedAt'];
    final editedAt = d['editedAt'];
    final coverStyle = d['coverStyle'];
    final paperColor = d['paperColor'];
    return Notebook(
      id: record.id,
      title: title,
      kind: NotebookKind.parse(kind),
      paper: PaperStyle.parse(paper),
      paperColor: d.containsKey('paperColor') || local == null
          ? PaperColor.parse(paperColor is String ? paperColor : null)
          : local.paperColor,
      coverColor: coverColor,
      coverStyle: d.containsKey('coverStyle') || local == null
          ? CoverStyle.parse(coverStyle is String ? coverStyle : null)
          : local.coverStyle,
      createdAt: createdAt,
      updatedAt: record.updatedAt,
      editedAt: editedAt is int ? editedAt : (local?.editedAt ?? record.updatedAt),
      folderId: d.containsKey('folderId') || local == null
          ? (folderId is String ? folderId : null)
          : local.folderId,
      favorite: d.containsKey('favorite') || local == null ? d['favorite'] == true : local.favorite,
      trashedAt: d.containsKey('trashedAt') || local == null
          ? (trashedAt is int ? trashedAt : null)
          : local.trashedAt,
    );
  }

  void _write(Notebook n, {required String deviceId, required bool dirty}) {
    db.execute(
      '''
      INSERT OR REPLACE INTO notebooks (id, title, kind, paper, cover_color,
                                        created_at, updated_at, device_id,
                                        deleted, dirty, folder_id, favorite,
                                        trashed_at, cover_style, edited_at,
                                        paper_color)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?)''',
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
        n.folderId,
        n.favorite ? 1 : 0,
        n.trashedAt,
        n.coverStyle.name,
        n.editedAt,
        n.paperColor.name,
      ],
    );
  }

  static Notebook _rowToNotebook(Row row) => Notebook(
    id: row['id'] as String,
    title: row['title'] as String,
    kind: NotebookKind.parse(row['kind'] as String),
    paper: PaperStyle.parse(row['paper'] as String),
    paperColor: PaperColor.parse(row['paper_color'] as String?),
    coverColor: row['cover_color'] as int,
    coverStyle: CoverStyle.parse(row['cover_style'] as String?),
    createdAt: row['created_at'] as int,
    updatedAt: row['updated_at'] as int,
    editedAt: row['edited_at'] as int,
    folderId: row['folder_id'] as String?,
    favorite: row['favorite'] == 1,
    trashedAt: row['trashed_at'] as int?,
  );
}
