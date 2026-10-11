import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../../ink/selection/selection_controller.dart';
import '../../../ink/tool_settings.dart';
import '../../../ink/tools/lasso_tool.dart';
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
/// one into the other are copied there, and tools can be linked (one tool,
/// colour and width for both). Two views of one notebook need nothing from
/// here: they share the notebook's models (`SharedNotebook`). Owned by the
/// editor workspace; editors [attach] while shown.
class SplitController extends ChangeNotifier {
  SplitController(this.tabs) {
    tabs.addListener(_onTabs);
    tabs.captureViews = _captureViews;
  }

  final OpenNotebooks tabs;

  /// Whether the screen is large enough for two panes (tablets in
  /// landscape, desktops); set by the workspace.
  bool available = false;

  final List<SplitPane> _panes = [];
  final Map<SplitPane, VoidCallback> _toolListeners = {};

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

  /// Whether [pane] is on screen: the presenting pane alone, else the
  /// first pane, and the second while there is room for it.
  bool isShown(SplitPane pane) {
    final presenting = _presenting;
    if (presenting != null) return pane == presenting;
    return available || !pane.secondary;
  }

  /// Starts tracking [pane] (an editor shown in the workspace).
  void attach(SplitPane pane) {
    _panes.add(pane);
    pane.session.content.lasso.dragOut = _DragOut(this, pane);
    void onTools() => _toolsChanged(pane);
    _toolListeners[pane] = onTools;
    pane.session.tools.addListener(onTools);
    // A pane opened while tools are linked starts with the other's.
    final other = _other(pane);
    if (tabs.linkTools && other != null) pane.session.tools.adopt(other.session.tools);
  }

  void detach(SplitPane pane) {
    _panes.remove(pane);
    pane.session.content.lasso.dragOut = null;
    final listener = _toolListeners.remove(pane);
    if (listener != null) pane.session.tools.removeListener(listener);
    if (_dropTarget == pane) _dropTarget = null;
    if (_dragSource == pane) _dragSource = null;
    if (_presenting == pane) {
      // The presenting editor went (its tab closed or switched, the split
      // closed): show the other pane again. Deferred, as editors detach
      // while the tree is locked (dispose).
      _presenting = null;
      scheduleMicrotask(() {
        if (!_disposed) notifyListeners();
      });
    }
  }

  /// Records where the shown editors look, before the tabs change.
  void _captureViews() {
    for (final pane in _panes) {
      if (pane.secondary) {
        if (pane.notebookId == tabs.splitId) tabs.splitView = pane.session.viewState;
      } else if (pane.notebookId == tabs.activeId) {
        tabs.saveView(pane.notebookId, pane.session.viewState);
      }
    }
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
  // Dragging selections between panes

  void _dragging(SplitPane from, Offset pointer, Offset centre) {
    final target = _targetAt(from, pointer);
    if (target == null && _dropTarget == null) return;
    _dropTarget = target;
    _dragSource = from;
    _dragCentre = from.toGlobal(centre);
    notifyListeners();
  }

  bool _drop(SplitPane from, Offset pointer, Offset centre) {
    final target = _targetAt(from, pointer);
    if (target == null) return false;
    target.receive(from.session.content.selection, target.toLocal(from.toGlobal(centre)));
    return true;
  }

  /// The other pane, if shown and under [pointer] (in [from]).
  SplitPane? _targetAt(SplitPane from, Offset pointer) {
    final global = from.toGlobal(pointer);
    return _panes.where((p) => p != from && isShown(p) && p.contains(global)).firstOrNull;
  }

  void _endDrag() {
    _dragSource = null;
    if (_dropTarget == null) return;
    _dropTarget = null;
    notifyListeners();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    tabs.removeListener(_onTabs);
    if (tabs.captureViews == _captureViews) tabs.captureViews = null;
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
