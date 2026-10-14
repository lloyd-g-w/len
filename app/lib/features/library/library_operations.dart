part of 'library_controller.dart';

/// The library's operations on notebooks and folders: each writes through
/// the repositories, then reloads and syncs in the background.
mixin _LibraryOperations {
  AppServices get services;
  LibrarySection get _section;
  String? get _folderId;
  bool get isSearching;
  List<Folder> get _folders;
  List<Notebook> get _notebooks;
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

  void updateFolder(Folder folder) => _run(() => services.folders.update(folder));

  /// Moves a folder; false if that would put it inside itself.
  bool moveFolder(String id, String? parentId) {
    final moved = services.folders.move(id, parentId) != null;
    if (moved) _changed();
    return moved;
  }

  /// The notebooks in folder [id] and its subfolders, at any depth.
  List<Notebook> notebooksIn(String id) {
    final subtree = services.folders.subtreeOf(id);
    return [
      for (final n in _notebooks)
        if (subtree.contains(n.folderId)) n,
    ];
  }

  /// What deleting folder [id] takes with it: its subfolders (at any
  /// depth) and the notebooks in it and them.
  ({int folders, int notebooks}) contentsOf(String id) {
    final subtree = services.folders.subtreeOf(id);
    return (
      folders: subtree.length - 1,
      notebooks: _notebooks.where((n) => subtree.contains(n.folderId)).length,
    );
  }

  /// Deletes a folder with its subfolders; their notebooks go to the trash.
  /// Returns what [undoDeleteFolder] needs to put it all back.
  FolderDeletion deleteFolder(String id) {
    late final FolderDeletion deletion;
    _run(
      () => services.database.transaction(() {
        final subtree = services.folders.subtreeOf(id);
        deletion = (
          folders: [
            for (final f in _folders)
              if (subtree.contains(f.id)) f,
          ],
          notebookIds: [
            for (final n in _notebooks)
              if (subtree.contains(n.folderId)) n.id,
          ],
        );
        services.notebooks.trashAllIn(services.folders.delete(id));
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
  void setFavorite(String id, bool value) => _run(() => services.notebooks.setFavorite(id, value));
  void moveNotebook(String id, String? folderId) =>
      _run(() => services.notebooks.moveTo(id, folderId));
  void trashNotebook(String id) => _run(() => services.notebooks.trash(id));
  void restoreNotebook(String id) => _run(() => services.notebooks.restore(id));
  void deleteForever(String id) => _run(() => services.notebooks.delete(id));
  void emptyTrash() => _run(services.notebooks.emptyTrash);

  Notebook? duplicate(String id) {
    final copy = services.notebooks.duplicate(id);
    _changed();
    return copy;
  }

  void _run(void Function() action) {
    action();
    _changed();
  }

  void _changed() {
    reload();
    unawaited(services.sync.syncInBackground());
  }
}
