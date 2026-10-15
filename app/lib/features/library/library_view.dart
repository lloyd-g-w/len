part of 'library_controller.dart';

/// What the library shows: the open folder's path, subfolders and
/// notebooks (filtered and sorted), the Recent row and where things are.
mixin _LibraryView on _LibraryState {
  LibrarySort get sort;
  bool get isSearching;

  /// Folders from the root down to the open folder.
  List<Folder> get breadcrumbs {
    final path = <Folder>[];
    var current = _folderById[_folderId];
    while (current != null && path.length <= _folders.length) {
      path.insert(0, current);
      current = _folderById[parentOf(current)];
    }
    return path;
  }

  /// The effective parent of [folder] (cycle- and orphan-safe).
  String? parentOf(Folder folder) => _parentById.containsKey(folder.id)
      ? _parentById[folder.id]
      : FolderRepository.effectiveParentOf(folder, _folderById);

  /// Subfolders of [parentId] (null = top level), by name.
  List<Folder> childrenOf(String? parentId) => _childrenByParent[parentId] ?? const [];

  /// Folders shown in the content area.
  List<Folder> get visibleFolders {
    if (_section != LibrarySection.library) return const [];
    if (isSearching) {
      final matches = LibraryQuery.matcher(_query);
      return [
        for (final f in _folders)
          if (matches(f.name)) f,
      ];
    }
    return childrenOf(_folderId);
  }

  /// Notebooks shown in the content area, filtered and sorted. A search in
  /// the library spans every folder.
  List<Notebook> get visibleNotebooks {
    final sort = this.sort;
    final cached = _visible;
    if (cached != null && cached.sort == sort) return cached.notebooks;
    final notebooks = _computeVisibleNotebooks(sort);
    _visible = (sort: sort, notebooks: notebooks);
    return notebooks;
  }

  List<Notebook> _computeVisibleNotebooks(LibrarySort sort) {
    final Iterable<Notebook> scope = switch (_section) {
      LibrarySection.library when isSearching => _notebooks,
      LibrarySection.library => _notebooks.where(
        (n) => LibraryQuery.folderOf(n, _folderById) == _folderId,
      ),
      LibrarySection.favorites => _notebooks.where((n) => n.favorite),
      LibrarySection.trash => _trash,
    };
    final matches = LibraryQuery.matcher(_query);
    // A search finds notebooks by their recordings' titles too.
    final matching = scope.where(
      (n) => matches(n.title) || (isSearching && (_recordingTitles[n.id]?.any(matches) ?? false)),
    );
    // The trash lists the most recently deleted first, whatever the sort.
    if (_section == LibrarySection.trash) return matching.toList();
    final sorted = LibraryQuery.sorted(matching, sort);
    final folder = _folderId;
    if (!isSearching || folder == null) return sorted;
    // A search started in a folder spans the library, but lists what is in
    // that folder (or below it) first (UX_AUDIT R16-8).
    final inside = [
      for (final n in sorted)
        if (_isWithin(n, folder)) n,
    ];
    return [
      ...inside,
      for (final n in sorted)
        if (!_isWithin(n, folder)) n,
    ];
  }

  /// Whether [notebook] is in folder [folderId] or one of its subfolders.
  bool _isWithin(Notebook notebook, String folderId) {
    String? current = LibraryQuery.folderOf(notebook, _folderById);
    for (var depth = 0; current != null && depth <= _folders.length; depth++) {
      if (current == folderId) return true;
      current = _parentById[current];
    }
    return false;
  }

  /// The library root's Recent row (UX_AUDIT R7-6): the notebooks opened
  /// lately, most recent first. Only at the root and not while searching,
  /// and only while one of them lives in a folder (else they are all in
  /// the grid below anyway).
  /// Trashed and deleted notebooks are skipped, and the next ones fill
  /// their places (R8-10).
  List<Notebook> get recentNotebooks {
    if (_section != LibrarySection.library || _folderId != null || isSearching) return const [];
    final byId = {for (final n in _notebooks) n.id: n};
    final recent = [for (final id in _recentIds) ?byId[id]].take(recentShown).toList();
    return recent.any((n) => LibraryQuery.folderOf(n, _folderById) != null) ? recent : const [];
  }

  /// How many notebooks the Recent row shows (of the more the workspace
  /// remembers, so trashed ones leave no gaps).
  static const int recentShown = 8;

  /// While searching, the title of [notebook]'s recording that matched,
  /// when its own title didn't (the result says why it is there, R8-11).
  String? recordingMatchOf(Notebook notebook) {
    if (!isSearching) return null;
    final matches = LibraryQuery.matcher(_query);
    if (matches(notebook.title)) return null;
    for (final title in _recordingTitles[notebook.id] ?? const <String>[]) {
      if (matches(title)) return title;
    }
    return null;
  }

  /// Number of notebooks and subfolders directly in [folderId].
  int itemCountIn(String folderId) =>
      childrenOf(folderId).length + (_notebookCountByFolder[folderId] ?? 0);

  /// "School › Maths" location of a notebook (for search results);
  /// "Library" at the top level.
  String locationOf(Notebook notebook) => folderPathOf(notebook) ?? 'Library';

  /// "School › Maths", the folders a notebook is filed in; null at the top
  /// level (the Recent row says nothing there).
  String? folderPathOf(Notebook notebook) => LibraryQuery.pathOf(notebook, _folderById);

  /// The folder [notebook] is shown in; null at the top level.
  Folder? folderOf(Notebook notebook) => _folderById[LibraryQuery.folderOf(notebook, _folderById)];

  Folder? folderById(String? id) => _folderById[id];
}
