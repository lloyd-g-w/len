import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../../ink/selection/selection_controller.dart';
import '../../../ink/tool_settings.dart';
import '../../../ink/tools/lasso_tool.dart';
import '../../../sync/sync_engine.dart';
import '../editor_session.dart';
import '../tabs/open_notebooks.dart';

/// One editor of the split view, as the [SplitController] sees it.
class SplitPane {
  SplitPane({required this.session, required this.secondary, required this.area});

  final EditorSession session;

  /// The second (right) pane.
  final bool secondary;

  /// The editor's area (its surface's coordinate space).
  final RenderBox? Function() area;

  String get notebookId => session.notebook.id;

  RenderBox? get _box {
    final box = area();
    return box != null && box.attached && box.hasSize ? box : null;
  }

  /// Whether global point [global] lies in this editor.
  bool contains(Offset global) {
    final box = _box;
    return box != null && (Offset.zero & box.size).contains(box.globalToLocal(global));
  }

  Offset toGlobal(Offset local) => _box?.localToGlobal(local) ?? local;
  Offset toLocal(Offset global) => _box?.globalToLocal(global) ?? global;

  /// Adds a copy of a selection dropped here, centred at [local], selected
  /// with the lasso (on the page under it, in paged notebooks).
  void receive(SelectionController from, Offset local) {
    final s = session;
    s.doc?.activateAt(local);
    s.tools.tool = EditorTool.lasso;
    final bounds = SelectionController.boundsOf(from.strokes, from.elements);
    s.content.selection.pasteItems(from.strokes, from.elements, bounds, s.viewport.toWorld(local));
  }
}

/// Coordinates the two editors of a split view: selections dragged from
/// one into the other are copied there, two views of one notebook stay
/// current with each other's edits, and tools can be linked (one tool,
/// colour and width for both). Owned by the editor workspace; editors
/// [attach] while shown.
class SplitController extends ChangeNotifier {
  SplitController(this.tabs) {
    tabs.addListener(_onTabs);
  }

  final OpenNotebooks tabs;

  /// Whether the screen is large enough for two panes (tablets in
  /// landscape, desktops); set by the workspace.
  bool available = false;

  final List<SplitPane> _panes = [];
  final Map<SplitPane, VoidCallback> _toolListeners = {};
  final Map<SplitPane, VoidCallback> _docListeners = {};

  /// The pane a dragged selection would be dropped into.
  SplitPane? get dropTarget => _dropTarget;
  SplitPane? _dropTarget;

  /// The pane a selection is dragged from, and where (global) its centre
  /// is, while over [dropTarget].
  SplitPane? get dragSource => _dragSource;
  SplitPane? _dragSource;
  Offset get dragCentre => _dragCentre;
  Offset _dragCentre = Offset.zero;

  /// The pane shown alone while it presents (the other stays alive).
  SplitPane? get presenting => _presenting;
  SplitPane? _presenting;

  bool get isSplit => available && tabs.splitId != null;

  /// Starts tracking [pane] (an editor shown in the workspace).
  void attach(SplitPane pane) {
    _panes.add(pane);
    pane.session.onSurfaceEdited = (surfaceId) => _edited(pane, surfaceId);
    pane.session.content.lasso.dragOut = _DragOut(this, pane);
    void onTools() => _toolsChanged(pane);
    _toolListeners[pane] = onTools;
    pane.session.tools.addListener(onTools);
    if (pane.session.doc case final doc?) {
      var pages = doc.pages;
      void onDoc() {
        if (identical(doc.pages, pages)) return;
        pages = doc.pages;
        if (!_flushing) _pagesChanged(pane); // Not the reload of a mirrored change.
      }

      _docListeners[pane] = onDoc;
      doc.addListener(onDoc);
    }
    // A pane opened while tools are linked starts with the other's.
    final other = _other(pane);
    if (tabs.linkTools && other != null) pane.session.tools.adopt(other.session.tools);
  }

  void detach(SplitPane pane) {
    _panes.remove(pane);
    pane.session.onSurfaceEdited = null;
    pane.session.content.lasso.dragOut = null;
    final listener = _toolListeners.remove(pane);
    if (listener != null) pane.session.tools.removeListener(listener);
    final docListener = _docListeners.remove(pane);
    if (docListener != null) pane.session.doc?.removeListener(docListener);
    _pending.remove(pane);
    _pendingPages.remove(pane);
    if (_dropTarget == pane) _dropTarget = null;
    if (_dragSource == pane) _dragSource = null;
    if (_presenting == pane) _presenting = null;
  }

  SplitPane? _other(SplitPane pane) => _panes.where((p) => p != pane).firstOrNull;

  /// Shows [pane] alone (presentation), or both again with null.
  void present(SplitPane? pane) {
    if (_presenting == pane) return;
    _presenting = pane;
    notifyListeners();
  }

  void _onTabs() {
    // Linking tools: the active editor's tools win.
    if (tabs.linkTools && _panes.length == 2) {
      final primary = _panes.firstWhere((p) => !p.secondary, orElse: () => _panes.first);
      _other(primary)?.session.tools.adopt(primary.session.tools);
    }
  }

  // ---------------------------------------------------------------------------
  // Linked tools

  bool _adopting = false;

  void _toolsChanged(SplitPane pane) {
    if (!tabs.linkTools || _adopting) return;
    final other = _other(pane);
    if (other == null) return;
    _adopting = true;
    try {
      other.session.tools.adopt(pane.session.tools);
    } finally {
      _adopting = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Two views of one notebook

  /// Surfaces edited in a pane, waiting to be reloaded in the other.
  final Map<SplitPane, Set<String>> _pending = {};

  /// Panes whose notebook's page list changed in the other.
  final Set<SplitPane> _pendingPages = {};
  Timer? _flush;
  bool _flushing = false;

  /// How long edits gather before the other view reloads.
  static const Duration mirrorDelay = Duration(milliseconds: 250);

  Iterable<SplitPane> _sameNotebook(SplitPane pane) =>
      _panes.where((p) => p != pane && p.notebookId == pane.notebookId);

  void _edited(SplitPane from, String surfaceId) {
    for (final other in _sameNotebook(from)) {
      (_pending[other] ??= {}).add(surfaceId);
    }
    _scheduleFlush();
  }

  void _pagesChanged(SplitPane from) {
    _pendingPages.addAll(_sameNotebook(from));
    _scheduleFlush();
  }

  void _scheduleFlush() {
    if (_pending.isEmpty && _pendingPages.isEmpty) return;
    _flush ??= Timer(mirrorDelay, flushEdits);
  }

  /// Reloads what one view of a notebook changed in the other now.
  void flushEdits() {
    _flush?.cancel();
    _flush = null;
    final pending = Map.of(_pending);
    final pages = {..._pendingPages};
    _pending.clear();
    _pendingPages.clear();
    for (final pane in {...pending.keys, ...pages}) {
      if (!_panes.contains(pane)) continue;
      final changes = RemoteChanges()..strokeSurfaces.addAll(pending[pane] ?? const {});
      if (pages.contains(pane)) changes.pagesOfNotebooks.add(pane.notebookId);
      _flushing = true;
      try {
        pane.session.applyRemoteChanges(changes);
      } finally {
        _flushing = false;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Dragging selections between panes

  void _dragging(SplitPane from, Offset pointer, Offset centre) {
    final global = from.toGlobal(pointer);
    final target = _panes.where((p) => p != from && p.contains(global)).firstOrNull;
    if (target == null && _dropTarget == null) return;
    _dropTarget = target;
    _dragSource = from;
    _dragCentre = from.toGlobal(centre);
    notifyListeners();
  }

  bool _drop(SplitPane from, Offset pointer, Offset centre) {
    final global = from.toGlobal(pointer);
    final target = _panes.where((p) => p != from && p.contains(global)).firstOrNull;
    if (target == null) return false;
    target.receive(from.session.content.selection, target.toLocal(from.toGlobal(centre)));
    return true;
  }

  void _endDrag() {
    _dragSource = null;
    if (_dropTarget == null) return;
    _dropTarget = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _flush?.cancel();
    tabs.removeListener(_onTabs);
    for (final pane in [..._panes]) {
      detach(pane);
    }
    super.dispose();
  }
}

class _DragOut implements SelectionDragOut {
  _DragOut(this.split, this.pane);

  final SplitController split;
  final SplitPane pane;

  @override
  void dragging(Offset pointer, Offset centre) => split._dragging(pane, pointer, centre);

  @override
  bool drop(Offset pointer, Offset centre) => split._drop(pane, pointer, centre);

  @override
  void end() => split._endDrag();
}
