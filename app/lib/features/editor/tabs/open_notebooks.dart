import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../../domain/notebook.dart';

/// Where an editor was looking, remembered per tab while it is not shown
/// and per notebook across launches ([encode] / [decode]).
@immutable
class EditorViewState {
  const EditorViewState({
    required this.scale,
    required this.offset,
    this.page = 0,
    this.size,
    this.fit,
  });

  /// Viewport zoom and pan (`screen = world * scale + offset`).
  final double scale;
  final Offset offset;

  /// The current page of a paged notebook.
  final int page;

  /// The viewport's size when the view was saved: a different size (a
  /// rotated tablet, a resized window) re-fits instead of restoring.
  final Size? size;

  /// How a paged notebook fits pages (`PageFit.name`), if chosen.
  final String? fit;

  /// Whether this view was saved at [other] size (or the size is unknown).
  bool fitsSize(Size other) {
    final s = size;
    return s == null || ((s.width - other.width).abs() < 1 && (s.height - other.height).abs() < 1);
  }

  /// A compact text form for the settings store.
  String encode() => [
    scale,
    offset.dx,
    offset.dy,
    page,
    size?.width ?? '',
    size?.height ?? '',
    fit ?? '',
  ].join(',');

  /// Parses [encode]'s output; null if [text] is missing or malformed.
  static EditorViewState? decode(String? text) {
    final parts = text?.split(',');
    if (parts == null || parts.length < 4) return null;
    final scale = double.tryParse(parts[0]);
    final dx = double.tryParse(parts[1]), dy = double.tryParse(parts[2]);
    final page = int.tryParse(parts[3]);
    if (scale == null || !scale.isFinite || scale <= 0 || dx == null || dy == null) return null;
    final w = parts.length > 5 ? double.tryParse(parts[4]) : null;
    final h = parts.length > 5 ? double.tryParse(parts[5]) : null;
    final fit = parts.length > 6 && parts[6].isNotEmpty ? parts[6] : null;
    return EditorViewState(
      scale: scale,
      offset: Offset(dx, dy),
      page: page ?? 0,
      size: w == null || h == null ? null : Size(w, h),
      fit: fit,
    );
  }
}

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

  /// Opens [notebook] in a tab (after the active one) and activates it.
  void open(Notebook notebook) {
    if (!contains(notebook.id)) {
      final at = _tabs.indexWhere((t) => t.id == _activeId);
      final tab = OpenTab(id: notebook.id, title: notebook.title, kind: notebook.kind);
      _tabs.insert(at == -1 ? _tabs.length : at + 1, tab);
      while (_tabs.length > maxTabs) {
        final victim = _recent.firstWhere((id) => id != notebook.id);
        _remove(victim);
      }
    }
    _activate(notebook.id);
    notifyListeners();
  }

  /// Shows tab [id].
  void activate(String id) {
    if (id == _activeId || !contains(id)) return;
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

  /// Whether both panes use the same tool, colours and widths.
  bool get linkTools => _linkTools;
  bool _linkTools = false;
  set linkTools(bool value) {
    if (value == _linkTools) return;
    _linkTools = value;
    notifyListeners();
  }

  /// Shows tab [id] in the second pane.
  void openSplit(String id) {
    if (!contains(id) || id == _splitId) return;
    _splitId = id;
    splitView = id == _activeId ? null : _views[id];
    notifyListeners();
  }

  /// Swaps the panes' notebooks.
  void swapSplit() {
    final other = _splitId, active = _activeId;
    if (other == null || active == null || other == active) return;
    _splitId = active;
    splitView = _views[active];
    _activate(other);
    notifyListeners();
  }

  /// Back to one pane.
  void closeSplit() {
    if (_splitId == null) return;
    _splitId = null;
    splitView = null;
    notifyListeners();
  }

  /// Closes tab [id]; closing the active tab shows its neighbour.
  void close(String id) {
    final i = _tabs.indexWhere((t) => t.id == id);
    if (i == -1) return;
    _remove(id);
    if (id == _activeId) {
      _activeId = null;
      if (_tabs.isNotEmpty) _activate(_tabs[i.clamp(0, _tabs.length - 1)].id);
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
