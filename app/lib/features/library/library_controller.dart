import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app_services.dart';
import '../../data/folder_repository.dart';
import '../../data/surface_stats.dart';
import '../../domain/cover_style.dart';
import '../../domain/folder.dart';
import '../../domain/notebook.dart';
import '../../domain/paper.dart';
import '../../domain/preferences.dart';
import '../../domain/tag.dart';
import 'library_query.dart';

/// Top-level places in the library navigation.
enum LibrarySection { library, favorites, trash }

/// State of the library screen: where the user is, what is shown, and the
/// operations on notebooks and folders. Reads everything from the
/// repositories on [reload]; libraries are small, so filtering and sorting
/// happen in memory.
class LibraryController extends ChangeNotifier {
  LibraryController(this.services) {
    reload();
  }

  final AppServices services;

  LibrarySection _section = LibrarySection.library;
  String? _folderId;
  String _query = '';

  List<Folder> _folders = const [];
  Map<String, Folder> _folderById = const {};
  List<Notebook> _notebooks = const [];
  List<Notebook> _trash = const [];

  List<Tag> _tags = const [];
  Map<String, Tag> _tagById = const {};

  /// Tag ids per notebook id (live tags only).
  Map<String, Set<String>> _notebookTags = const {};
  Map<String, int> _tagCounts = const {};

  /// Tags every shown notebook must carry (chips, or a tag in the sidebar).
  Set<String> _tagFilter = const {};

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
  bool get isSearching => _query.trim().isNotEmpty;

  /// The search split into free text and `tag:` terms.
  ParsedQuery get parsedQuery => LibraryQuery.parse(_query);

  /// Whether a search or a tag filter spans every folder.
  bool get isFiltering => isSearching || _tagFilter.isNotEmpty;

  /// The user's tags, by name.
  List<Tag> get tags => _tags;
  Tag? tagById(String id) => _tagById[id];

  /// Tags on notebook [id], by name.
  List<Tag> tagsOf(String id) => [
    for (final t in _tags)
      if (_notebookTags[id]?.contains(t.id) ?? false) t,
  ];

  /// Notebooks (not in the trash) carrying tag [id].
  int notebookCountOf(String tagId) => _tagCounts[tagId] ?? 0;

  /// Tags every shown notebook must carry.
  Set<String> get tagFilter => _tagFilter;

  /// Adds tag [id] to the filter, or takes it out.
  void toggleTagFilter(String id) {
    final next = {..._tagFilter};
    if (!next.remove(id)) next.add(id);
    _tagFilter = next;
    notifyListeners();
  }

  void clearTagFilter() {
    if (_tagFilter.isEmpty) return;
    _tagFilter = const {};
    notifyListeners();
  }

  /// Shows every notebook tagged [id] (the sidebar's tag entries).
  void showTag(String id) {
    _section = LibrarySection.library;
    _folderId = null;
    _query = '';
    _tagFilter = {id};
    notifyListeners();
  }

  /// Whether the library shows exactly tag [id] from the sidebar.
  bool isShowingTag(String id) =>
      _section == LibrarySection.library &&
      _folderId == null &&
      _tagFilter.length == 1 &&
      _tagFilter.first == id;

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
  void reload() {
    _folders = services.folders.list();
    _folderById = {for (final f in _folders) f.id: f};
    _notebooks = services.notebooks.list();
    _trash = services.notebooks.trashed();
    _pageCounts = SurfaceStats(services.database).pageCounts();
    _tags = services.tags.list();
    _tagById = {for (final t in _tags) t.id: t};
    _notebookTags = services.tags.taggings.all(TagTarget.notebook);
    _tagCounts = {};
    for (final n in _notebooks) {
      for (final t in _notebookTags[n.id] ?? const <String>{}) {
        _tagCounts[t] = (_tagCounts[t] ?? 0) + 1;
      }
    }
    if (_tagFilter.any((id) => !_tagById.containsKey(id))) {
      _tagFilter = {..._tagFilter.where(_tagById.containsKey)};
    }
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
    _tagFilter = const {};
    notifyListeners();
  }

  /// Opens [folderId] (null = library root) in the library section.
  void openFolder(String? folderId) {
    _section = LibrarySection.library;
    _folderId = _folderById.containsKey(folderId) ? folderId : null;
    _query = '';
    _tagFilter = const {};
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
    if (_section != LibrarySection.library || _tagFilter.isNotEmpty) return const [];
    if (isSearching) {
      final parsed = parsedQuery;
      if (parsed.tags.isNotEmpty) return const [];
      final matches = LibraryQuery.matcher(parsed.text);
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
      LibrarySection.library when isFiltering => _notebooks,
      LibrarySection.library => _notebooks.where(
        (n) => LibraryQuery.folderOf(n, _folderById) == _folderId,
      ),
      LibrarySection.favorites => _notebooks.where((n) => n.favorite),
      LibrarySection.trash => _trash,
    };
    final matches = LibraryQuery.matcher(parsedQuery.text);
    final matching = scope.where((n) => matches(n.title) && matchesTags(n));
    // The trash lists the most recently deleted first, whatever the sort.
    return _section == LibrarySection.trash
        ? matching.toList()
        : LibraryQuery.sorted(matching, sort);
  }

  /// Whether [notebook] carries the tags of the tag filter and of the
  /// search's `tag:` terms (the trash ignores the tag filter).
  bool matchesTags(Notebook notebook) {
    final ids = _notebookTags[notebook.id] ?? const <String>{};
    if (_section != LibrarySection.trash && !ids.containsAll(_tagFilter)) return false;
    final terms = parsedQuery.tags;
    return terms.isEmpty ||
        LibraryQuery.hasTags([for (final id in ids) ?_tagById[id]?.name], terms);
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

  // ---------------------------------------------------------------------------
  // Operations

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
    CoverStyle coverStyle = CoverStyle.plain,
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
      coverStyle: coverStyle,
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

  Folder createFolder(String name, {required int color, String? icon}) {
    final parent = _section == LibrarySection.library && !isFiltering ? _folderId : null;
    final folder = services.folders.create(name: name, parentId: parent, color: color, icon: icon);
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

  /// Deletes a folder with its subfolders; their notebooks go to the trash.
  void deleteFolder(String id) => _run(
    () => services.database.transaction(() {
      services.notebooks.trashAllIn(services.folders.delete(id));
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

  /// Makes [tagIds] exactly the tags on notebook [id].
  void setNotebookTags(String id, Set<String> tagIds) =>
      _run(() => services.tags.taggings.setTags(id, TagTarget.notebook, tagIds));

  /// Puts tags on every notebook of [ids] (true) or takes them off
  /// (false), as chosen in the tag picker.
  void applyTagChanges(Iterable<String> ids, Map<String, bool> changes) => _run(
    () => services.database.transaction(() {
      changes.forEach((tagId, on) {
        for (final id in ids) {
          services.tags.taggings.set(tagId, id, TagTarget.notebook, on: on);
        }
      });
    }),
  );

  /// Creates a tag (or returns the one of that name).
  Tag createTag(String name, {required int color}) {
    final tag = services.tags.create(name: name, color: color);
    _changed();
    return tag;
  }

  void updateTag(Tag tag) => _run(() => services.tags.update(tag));
  void deleteTag(String id) => _run(() => services.tags.delete(id));

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
    unawaited(services.sync.syncNow());
  }
}
