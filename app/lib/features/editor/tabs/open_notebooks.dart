import 'package:flutter/foundation.dart';

import '../../../domain/notebook.dart';
import 'editor_view_state.dart';

export 'editor_view_state.dart';

/// One open notebook in the tab strip.
@immutable
class OpenTab {
  const OpenTab({required this.id, required this.title, required this.kind});

  final String id;
  final String title;
  final NotebookKind kind;

  OpenTab withTitle(String title) => OpenTab(id: id, title: title, kind: kind);
}

/// The notebooks open in the editor, GoodNotes-style tabs: one is active
/// (shown), the others keep their place ([EditorViewState]) in memory.
///
/// At most [maxTabs] stay open; opening one more closes the least recently
/// used. Lives in `AppServices`, so tabs survive going back to the library.
///
/// Split view (tablets in landscape, desktops) shows a second tab — or the
/// active notebook a second time — beside the active one ([splitId]).
class OpenNotebooks extends ChangeNotifier {
  OpenNotebooks({this.maxTabs = 8});

  final int maxTabs;

  final List<OpenTab> _tabs = [];
  final Map<String, EditorViewState> _views = {};

  /// Notebooks shown since the last [takeVisited] (their previews may
  /// need refreshing in the library).
  final Set<String> _visited = {};

  /// Returns and forgets the notebooks shown since the last call.
  Set<String> takeVisited() {
    final visited = {..._visited};
    _visited.clear();
    return visited;
  }

  /// Tab ids, most recently used last.
  final List<String> _recent = [];
  String? _activeId;

  List<OpenTab> get tabs => List.unmodifiable(_tabs);
  String? get activeId => _activeId;
  OpenTab? get active => _tabs.where((t) => t.id == _activeId).firstOrNull;
  bool get isEmpty => _tabs.isEmpty;
  int get length => _tabs.length;

  bool contains(String id) => _tabs.any((t) => t.id == id);

  /// Set by the shown editors' coordinator (the split view): records where
  /// the shown editors look now ([saveView], [splitView]) before the tabs
  /// change, so the editors created for the new layout start there.
  VoidCallback? captureViews;

  /// Opens [notebook] in a tab (after the active one) and activates it;
  /// with [view], shows it there (e.g. at a linked page).
  void open(Notebook notebook, {EditorViewState? view}) {
    captureViews?.call();
    if (!contains(notebook.id)) {
      final at = _tabs.indexWhere((t) => t.id == _activeId);
      final tab = OpenTab(id: notebook.id, title: notebook.title, kind: notebook.kind);
      _tabs.insert(at == -1 ? _tabs.length : at + 1, tab);
      while (_tabs.length > maxTabs) {
        // Never the tab shown in the split view's second pane (it is
        // shown, so not "least recently used").
        final victim = _recent.firstWhere(
          (id) => id != notebook.id && id != _splitId,
          orElse: () => _recent.firstWhere((id) => id != notebook.id),
        );
        _remove(victim);
      }
    }
    if (view != null) _views[notebook.id] = view;
    _activate(notebook.id);
    notifyListeners();
  }

  /// A notebook whose recordings list its editor shows once open
  /// ([requestRecordings]; Settings → Storage).
  String? _recordingsFor;

  /// Asks the editor of notebook [id] to show its recordings when it opens
  /// (or, already open, at the next change of tabs).
  void requestRecordings(String id) => _recordingsFor = id;

  /// Whether notebook [id]'s recordings were asked for; forgets the request.
  bool takeRecordingsRequest(String id) {
    if (_recordingsFor != id) return false;
    _recordingsFor = null;
    return true;
  }

  /// Shows tab [id].
  void activate(String id) {
    if (id == _activeId || !contains(id)) return;
    captureViews?.call();
    _activate(id);
    notifyListeners();
  }

  /// Activates the next (or with [backwards], the previous) tab, wrapping.
  void cycle({bool backwards = false}) {
    if (_tabs.length < 2) return;
    final i = _tabs.indexWhere((t) => t.id == _activeId);
    final next = (i + (backwards ? -1 : 1)) % _tabs.length;
    activate(_tabs[next].id);
  }

  // ---------------------------------------------------------------------------
  // Split view

  String? _splitId;

  /// The notebook shown in the split view's second pane, if any (it may be
  /// the active one: two places in one notebook).
  String? get splitId => _splitId;

  /// Where the second pane was looking when it closed.
  EditorViewState? splitView;

  /// The first pane's share of the width (0.25..0.75).
  double get splitFraction => _splitFraction;
  double _splitFraction = 0.5;
  set splitFraction(double value) => _splitFraction = value.clamp(0.25, 0.75);

  /// Shows tab [id] in the second pane.
  void openSplit(String id) {
    if (!contains(id) || id == _splitId) return;
    captureViews?.call();
    _splitId = id;
    splitView = id == _activeId ? null : _views[id];
    notifyListeners();
  }

  /// Swaps the panes' notebooks; each keeps where it was looking.
  void swapSplit() {
    final other = _splitId, active = _activeId;
    if (other == null || active == null || other == active) return;
    captureViews?.call();
    final secondView = splitView;
    _splitId = active;
    splitView = _views[active];
    if (secondView != null) _views[other] = secondView;
    _activate(other);
    notifyListeners();
  }

  /// Back to one pane.
  void closeSplit() {
    if (_splitId == null) return;
    captureViews?.call();
    _splitId = null;
    splitView = null;
    notifyListeners();
  }

  /// Closes tab [id]; closing the active tab shows its neighbour. When
  /// that neighbour is the split view's second pane, the split closes and
  /// the notebook moves to the first pane where it was looking (rather
  /// than showing it twice).
  void close(String id) {
    final i = _tabs.indexWhere((t) => t.id == id);
    if (i == -1) return;
    captureViews?.call();
    _remove(id);
    if (id == _activeId) {
      _activeId = null;
      if (_tabs.isNotEmpty) {
        final next = _tabs[i.clamp(0, _tabs.length - 1)].id;
        if (next == _splitId) {
          if (splitView case final view?) _views[next] = view;
          _splitId = null;
          splitView = null;
        }
        _activate(next);
      }
    }
    notifyListeners();
  }

  /// Moves tab [id] to position [to].
  void move(String id, int to) {
    final i = _tabs.indexWhere((t) => t.id == id);
    if (i == -1) return;
    final tab = _tabs.removeAt(i);
    _tabs.insert(to.clamp(0, _tabs.length), tab);
    notifyListeners();
  }

  /// Keeps a tab's title in step with renames.
  void rename(String id, String title) {
    final i = _tabs.indexWhere((t) => t.id == id);
    if (i == -1 || _tabs[i].title == title) return;
    _tabs[i] = _tabs[i].withTitle(title);
    notifyListeners();
  }

  /// Remembers where tab [id] was looking (when its editor closes).
  void saveView(String id, EditorViewState view) {
    if (contains(id)) _views[id] = view;
  }

  /// Where tab [id] was looking, if known.
  EditorViewState? viewOf(String id) => _views[id];

  void _activate(String id) {
    _activeId = id;
    _visited.add(id);
    _recent
      ..remove(id)
      ..add(id);
  }

  void _remove(String id) {
    if (id == _splitId) {
      _splitId = null;
      splitView = null;
    }
    _tabs.removeWhere((t) => t.id == id);
    _views.remove(id);
    _recent.remove(id);
  }
}
