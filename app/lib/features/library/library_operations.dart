part of 'library_controller.dart';

/// The library's operations on notebooks and folders: each writes through
/// the repositories, then reloads and syncs in the background.
mixin _LibraryOperations {
  AppServices get services;
  LibrarySection get _section;
  String? get _folderId;
  bool get isSearching;
  void reload();

  /// Creates a notebook in the open folder; a paged notebook's first page
  /// is made from [firstPage] (default: a blank A4 page of [paper]); with
  /// [papers], one page per paper (a generated planner).
  Notebook createNotebook({
    required String title,
    required NotebookKind kind,
    required PaperStyle paper,
    PaperLook look = PaperLook.standard,
    required int coverColor,
    PaperColor paperColor = PaperColor.white,
    PageTemplate? firstPage,
    List<Paper> papers = const [],
  }) {
    final notebook = services.notebooks.create(
      title: title,
      kind: kind,
      paper: paper,
      look: look,
      paperColor: paperColor,
      coverColor: coverColor,
      folderId: _section == LibrarySection.library ? _folderId : null,
      firstPage: firstPage,
      papers: papers,
    );
    if (_section == LibrarySection.favorites) services.notebooks.setFavorite(notebook.id, true);
    _changed();
    return notebook;
  }

  /// Files a notebook created elsewhere (e.g. imported from a PDF) where
  /// [createNotebook] would have put it: the open folder, or favourites.
  /// Returns the up-to-date notebook.
  Notebook adoptNotebook(Notebook notebook) {
    final folderId = _section == LibrarySection.library ? _folderId : null;
    if (folderId != null) services.notebooks.moveTo(notebook.id, folderId);
    if (_section == LibrarySection.favorites) services.notebooks.setFavorite(notebook.id, true);
    _changed();
    return services.notebooks.get(notebook.id) ?? notebook;
  }

  Folder createFolder(String name, {required int color}) {
    // The open folder, also while searching in it (Favourites and Trash
    // have no folders: the top level).
    final parent = _section == LibrarySection.library ? _folderId : null;
    final folder = services.folders.create(name: name, parentId: parent, color: color);
    _changed();
    return folder;
  }

  /// Applies [edit] to folder [id] as the database holds it now (sync may
  /// have changed it since the last [reload]); returns the folder as it
  /// was, or null if it is gone.
  Folder? editFolder(String id, Folder Function(Folder folder) edit) {
    final before = services.folders.get(id);
    if (before != null) _run(() => services.folders.update(edit(before)));
    return before;
  }

  /// Moves a folder into [parentId] (null = top level; also when that was
  /// deleted meanwhile); returns the parent it had (for Undo), or null if it
  /// is gone or would land inside itself.
  ({String? from})? moveFolder(String id, String? parentId) {
    final from = services.folders.get(id)?.parentId;
    if (services.folders.move(id, _live(parentId)) == null) return null;
    _changed();
    return (from: from);
  }

  /// The notebooks in folder [id] and its subfolders, at any depth, as the
  /// database holds them.
  List<Notebook> notebooksIn(String id) {
    final subtree = services.folders.subtreeOf(id);
    return [
      for (final n in services.notebooks.list())
        if (subtree.contains(n.folderId)) n,
    ];
  }

  /// Deletes a folder with its subfolders; their notebooks go to the trash.
  /// Returns what [undoDeleteFolder] needs to put it all back: what the
  /// database held and trashed, not the library's last load (sync may have
  /// brought more in since).
  FolderDeletion deleteFolder(String id) {
    late final FolderDeletion deletion;
    _run(
      () => services.database.transaction(() {
        final subtree = services.folders.subtreeOf(id);
        final folders = [
          for (final f in services.folders.list())
            if (subtree.contains(f.id)) f,
        ];
        final deleted = services.folders.delete(id);
        deletion = (folders: folders, notebookIds: services.notebooks.trashAllIn(deleted));
      }),
    );
    return deletion;
  }

  /// Brings back the folders of [deletion] and the notebooks it trashed
  /// (those still in the trash), each in its own folder again.
  void undoDeleteFolder(FolderDeletion deletion) => _run(
    () => services.database.transaction(() {
      for (final f in deletion.folders) {
        services.folders.update(f);
      }
      for (final id in deletion.notebookIds) {
        if (services.notebooks.get(id)?.isTrashed ?? false) services.notebooks.restore(id);
      }
    }),
  );

  void updateNotebook(Notebook notebook) => _run(() => services.notebooks.update(notebook));

  /// Stars notebooks [ids] ([value]) or unstars them; returns those that
  /// changed.
  List<String> setFavorites(Iterable<String> ids, bool value) => _batch(ids, (id) {
    final notebook = services.notebooks.get(id);
    if (notebook == null || notebook.favorite == value) return false;
    services.notebooks.setFavorite(id, value);
    return true;
  });

  /// Moves notebooks [ids] into [folderId] (null = the library root; also
  /// when that was deleted meanwhile); returns the folder each one moved was
  /// in (for Undo). Notebooks gone or in the trash (by sync) stay put.
  Map<String, String?> moveNotebooks(Iterable<String> ids, String? folderId) {
    final from = <String, String?>{};
    final target = _live(folderId);
    _batch(ids, (id) {
      final notebook = services.notebooks.get(id);
      if (notebook == null || notebook.isTrashed) return false;
      from[id] = notebook.folderId;
      services.notebooks.moveTo(id, target);
      return true;
    });
    return from;
  }

  /// Moves notebooks [ids] to the trash; returns those it trashed (not
  /// those already there or gone), which Undo restores.
  List<String> trashNotebooks(Iterable<String> ids) => _batch(ids, (id) {
    final notebook = services.notebooks.get(id);
    if (notebook == null || notebook.isTrashed) return false;
    services.notebooks.trash(id);
    return true;
  });

  /// Takes notebooks [ids] out of the trash; returns them as restored
  /// (those that were in the trash).
  List<Notebook> restoreNotebooks(Iterable<String> ids) {
    final restored = _batch(ids, (id) {
      if (!(services.notebooks.get(id)?.isTrashed ?? false)) return false;
      services.notebooks.restore(id);
      return true;
    });
    return [for (final id in restored) ?services.notebooks.get(id)];
  }

  /// Deletes notebooks [ids] forever.
  void deleteForever(Iterable<String> ids) => _batch(ids, (id) {
    services.notebooks.delete(id);
    return true;
  });

  void emptyTrash() => _run(services.notebooks.emptyTrash);

  Notebook? duplicate(String id) {
    final copy = services.notebooks.duplicate(id);
    _changed();
    return copy;
  }

  /// [folderId] if that folder exists, else null (the top level).
  String? _live(String? folderId) =>
      folderId != null && services.folders.get(folderId) != null ? folderId : null;

  /// Applies [change] to each of [ids] in one transaction, then reloads
  /// once; returns the ids it changed.
  List<String> _batch(Iterable<String> ids, bool Function(String id) change) {
    late final List<String> changed;
    _run(
      () => services.database.transaction(() {
        changed = [
          for (final id in ids.toSet())
            if (change(id)) id,
        ];
      }),
    );
    return changed;
  }

  void _run(void Function() action) {
    action();
    _changed();
  }

  void _changed() {
    // A notebook recording unattended that was just trashed or deleted
    // stops and saves its recording (into the trash with it).
    services.sharedNotebooks.notebooksChanged();
    reload();
    unawaited(services.sync.syncInBackground());
  }
}
