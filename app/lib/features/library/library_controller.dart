import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app_services.dart';
import '../../data/folder_repository.dart';
import '../../data/surface_stats.dart';
import '../../domain/folder.dart';
import '../../domain/notebook.dart';
import '../../domain/paper.dart';
import '../../domain/preferences.dart';
import 'library_query.dart';

part 'library_operations.dart';

/// Folders removed by [LibraryController.deleteFolder] and the notebooks it
/// moved to the trash.
typedef FolderDeletion = ({List<Folder> folders, List<String> notebookIds});

/// Top-level places in the library navigation.
enum LibrarySection { library, favorites, trash }

/// State of the library screen: where the user is, what is shown, and the
/// operations on notebooks and folders. Reads everything from the
/// repositories on [reload]; libraries are small, so filtering and sorting
/// happen in memory.
class LibraryController extends ChangeNotifier with _LibraryOperations {
  LibraryController(this.services) {
    // Notebooks trashed more than 30 days ago go for good.
    if (services.notebooks.purgeTrash() > 0) unawaited(services.sync.syncNow());
    reload();
  }

  @override
  final AppServices services;

  @override
  LibrarySection _section = LibrarySection.library;
  @override
  String? _folderId;
  String _query = '';

  @override
  List<Folder> _folders = const [];
  Map<String, Folder> _folderById = const {};
  @override
  List<Notebook> _notebooks = const [];
  List<Notebook> _trash = const [];

  // Derived from the lists above on [reload], so building the sidebar tree
  // and folder tiles does not re-walk ancestor chains per folder.
  Map<String, String?> _parentById = const {};
  Map<String?, List<Folder>> _childrenByParent = const {};
  Map<String?, int> _notebookCountByFolder = const {};
  Map<String, int> _pageCounts = const {};

  /// [visibleNotebooks] for the current state and sort; several widgets
  /// read it per build. Cleared whenever listeners are notified.
  ({LibrarySort sort, List<Notebook> notebooks})? _visible;

  /// The notebook with keyboard focus (target of the Delete shortcut).
  String? get focusedNotebookId => _focusedNotebookId;
  String? _focusedNotebookId;

  /// Records that notebook [id] gained or lost keyboard focus. Losing focus
  /// only clears it if no other notebook has gained it meanwhile (focus
  /// gain and loss callbacks arrive in no guaranteed order).
  void setNotebookFocused(String id, bool focused) {
    if (focused) {
      _focusedNotebookId = id;
    } else if (_focusedNotebookId == id) {
      _focusedNotebookId = null;
    }
  }

  LibrarySection get section => _section;

  /// The open folder in [LibrarySection.library]; null = library root.
  String? get folderId => _folderId;
  Folder? get folder => _folderById[_folderId];
  String get query => _query;
  @override
  bool get isSearching => _query.trim().isNotEmpty;

  List<Folder> get allFolders => _folders;
  List<Notebook> get trash => _trash;

  /// Number of pages of paged notebook [id] (0 if unknown).
  int pageCountOf(String id) => _pageCounts[id] ?? 0;

  int get favoriteCount => _notebooks.where((n) => n.favorite).length;

  LibraryLayout get layout => services.preferences.libraryLayout;
  set layout(LibraryLayout value) {
    services.preferences.libraryLayout = value;
    notifyListeners();
  }

  LibrarySort get sort => services.preferences.librarySort;
  set sort(LibrarySort value) {
    services.preferences.librarySort = value;
    notifyListeners();
  }

  /// Re-reads folders and notebooks (after local or remote changes).
  @override
  void reload() {
    _folders = services.folders.list();
    _folderById = {for (final f in _folders) f.id: f};
    _notebooks = services.notebooks.list();
    _trash = services.notebooks.trashed();
    _pageCounts = SurfaceStats(services.database).pageCounts();
    _parentById = {
      for (final f in _folders) f.id: FolderRepository.effectiveParentOf(f, _folderById),
    };
    _childrenByParent = {};
    for (final f in _folders) {
      (_childrenByParent[_parentById[f.id]] ??= []).add(f);
    }
    _notebookCountByFolder = {};
    for (final n in _notebooks) {
      final folder = LibraryQuery.folderOf(n, _folderById);
      _notebookCountByFolder[folder] = (_notebookCountByFolder[folder] ?? 0) + 1;
    }
    if (_folderId != null && !_folderById.containsKey(_folderId)) _folderId = null;
    notifyListeners();
  }

  @override
  void notifyListeners() {
    _visible = null;
    super.notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Navigation

  void showSection(LibrarySection section) {
    _section = section;
    _folderId = null;
    notifyListeners();
  }

  /// Opens [folderId] (null = library root) in the library section.
  void openFolder(String? folderId) {
    _section = LibrarySection.library;
    _folderId = _folderById.containsKey(folderId) ? folderId : null;
    _query = '';
    notifyListeners();
  }

  /// Goes one level up; false if already at a top level.
  bool goUp() {
    if (_section != LibrarySection.library) {
      showSection(LibrarySection.library);
      return true;
    }
    if (_folderId == null) return false;
    openFolder(parentOf(_folderById[_folderId]!));
    return true;
  }

  set query(String value) {
    if (value == _query) return;
    _query = value;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // What is shown

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
    final matching = scope.where((n) => matches(n.title));
    // The trash lists the most recently deleted first, whatever the sort.
    return _section == LibrarySection.trash
        ? matching.toList()
        : LibraryQuery.sorted(matching, sort);
  }

  /// Number of notebooks and subfolders directly in [folderId].
  int itemCountIn(String folderId) =>
      childrenOf(folderId).length + (_notebookCountByFolder[folderId] ?? 0);

  /// "School › Maths" location of a notebook (for search results).
  String locationOf(Notebook notebook) {
    final names = <String>[];
    var current = _folderById[LibraryQuery.folderOf(notebook, _folderById)];
    while (current != null && names.length <= _folders.length) {
      names.insert(0, current.name);
      current = _folderById[parentOf(current)];
    }
    return names.isEmpty ? 'Library' : names.join(' › ');
  }

  Folder? folderById(String? id) => _folderById[id];
}
