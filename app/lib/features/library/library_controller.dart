import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app_services.dart';
import '../../data/folder_repository.dart';
import '../../data/surface_stats.dart';
import '../../domain/folder.dart';
import '../../domain/notebook.dart';
import '../../domain/paper.dart';
import '../../domain/preferences.dart';
import '../../sync/sync_controller.dart';
import 'library_query.dart';

part 'library_operations.dart';
part 'library_view.dart';

/// Folders removed by [LibraryController.deleteFolder] and the notebooks it
/// moved to the trash.
typedef FolderDeletion = ({List<Folder> folders, List<String> notebookIds});

/// Top-level places in the library navigation.
enum LibrarySection { library, favorites, trash }

/// State of the library screen: where the user is, what is shown, and the
/// operations on notebooks and folders. Reads everything from the
/// repositories on [reload]; libraries are small, so filtering and sorting
/// happen in memory.
class LibraryController extends _LibraryState with _LibraryOperations, _LibraryView {
  LibraryController(super.services) {
    reload();
    unawaited(_purgeTrash());
  }

  /// Deletes for good the notebooks trashed more than 30 days ago: after
  /// the first frame, one notebook per event-loop turn (one may hold
  /// thousands of strokes).
  Future<void> _purgeTrash() async {
    final expired = services.notebooks.expiredTrash();
    if (expired.isEmpty) return;
    for (final id in expired) {
      await Future<void>.delayed(Duration.zero);
      if (_disposed) return;
      // Unless restored meanwhile.
      services.notebooks.purgeIfExpired(id);
    }
    reload();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

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

  /// Number of audio recordings of notebook [id].
  int recordingCountOf(String id) => _recordingTitles[id]?.length ?? 0;

  /// Number of pages of paged notebook [id] (0 if unknown).
  int pageCountOf(String id) => _pageCounts[id] ?? 0;

  int get favoriteCount => _notebooks.where((n) => n.favorite).length;

  LibraryLayout get layout => services.preferences.libraryLayout;
  set layout(LibraryLayout value) {
    services.preferences.libraryLayout = value;
    notifyListeners();
  }

  @override
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
    _pageCounts = SurfaceStats(services.database).pageCounts();
    _notebooks = _unchangedKept(_arrived(services.notebooks.list()), _notebooks);
    _trash = _unchangedKept(services.notebooks.trashed(), _trash);
    _recentIds = services.workspace.recent;
    _recordingTitles = services.recordings.titlesByNotebook();
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

  /// [notebooks] but, while a sync runs, those whose pages are still on
  /// their way (a notebook's record may come before its pages): opened, it
  /// would start a blank page of its own, synced to every device.
  List<Notebook> _arrived(List<Notebook> notebooks) {
    if (services.sync.state != SyncState.syncing) return notebooks;
    return [
      for (final n in notebooks)
        if (n.kind != NotebookKind.paged || (_pageCounts[n.id] ?? 0) > 0) n,
    ];
  }

  /// [fresh] with the notebooks that did not change since [before] as the
  /// same objects, so their cards are not built again.
  static List<Notebook> _unchangedKept(List<Notebook> fresh, List<Notebook> before) {
    if (before.isEmpty) return fresh;
    final old = {for (final n in before) n.id: n};
    return [
      for (final n in fresh)
        if (old[n.id] case final kept? when kept.sameAs(n)) kept else n,
    ];
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
}

/// What [LibraryController] reads from the repositories on
/// [LibraryController.reload], and where the user is.
abstract class _LibraryState extends ChangeNotifier {
  _LibraryState(this.services);

  final AppServices services;

  LibrarySection _section = LibrarySection.library;
  String? _folderId;
  String _query = '';

  List<Folder> _folders = const [];
  Map<String, Folder> _folderById = const {};
  List<Notebook> _notebooks = const [];
  List<Notebook> _trash = const [];

  // Derived from the lists above on [LibraryController.reload], so building
  // the sidebar tree and folder tiles does not re-walk ancestor chains per
  // folder.
  Map<String, String?> _parentById = const {};
  Map<String?, List<Folder>> _childrenByParent = const {};
  Map<String?, int> _notebookCountByFolder = const {};
  Map<String, int> _pageCounts = const {};
  List<String> _recentIds = const [];
  Map<String, List<String>> _recordingTitles = const {};

  /// [_LibraryView.visibleNotebooks] for the current state and sort;
  /// several widgets read it per build. Cleared whenever listeners are
  /// notified.
  ({LibrarySort sort, List<Notebook> notebooks})? _visible;
}
