import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../../ink/selection/selection_controller.dart';
import '../../../ink/tool_settings.dart';
import '../../../ink/tools/lasso_tool.dart';
import '../editor_session.dart';
import '../tabs/open_notebooks.dart';

part 'split_pane.dart';

/// Coordinates the two editors of a split view: selections dragged from
/// one into the other are copied there, and tools are linked (one tool,
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

  /// The pane shown alone while in focus mode (the other stays alive).
  SplitPane? get soloPane => _solo;
  SplitPane? _solo;

  bool get isSplit => available && tabs.splitId != null;

  /// The pane used last (its first pointer contact or keyboard focus);
  /// null: none yet, the first pane counts.
  SplitPane? _active;

  /// [pane] was used: it gets full chrome, the other dims (REDESIGN §2.8).
  void use(SplitPane pane) {
    if (_active == pane) return;
    _active = pane;
    notifyListeners();
  }

  /// Whether [pane]'s chrome is dimmed: both panes are on screen and the
  /// other one was used last — but not while a selection dragged from the
  /// other pane would drop into it (its chrome would read as greyed out).
  bool isDimmed(SplitPane pane) {
    if (!isSplit || _solo != null || _panes.length < 2 || _dropTarget == pane) return false;
    final active = _active ?? _panes.where((p) => !p.secondary).firstOrNull;
    return active != null && active != pane;
  }

  /// Whether [pane] is on screen: the pane in focus mode alone, else the
  /// first pane, and the second while there is room for it.
  bool isShown(SplitPane pane) {
    final solo = _solo;
    if (solo != null) return pane == solo;
    return available || !pane.secondary;
  }

  /// The pane alive but not on screen (the second pane while there is no
  /// room for two, e.g. a tablet turned to portrait), if any.
  SplitPane? get parked {
    if (_solo != null) return null; // Focus mode shows one on purpose.
    return _panes.where((p) => !isShown(p)).firstOrNull;
  }

  /// Shows the [parked] pane's notebook here instead (swaps the panes).
  void showParked() {
    if (parked == null) return;
    tabs.swapSplit();
  }

  /// Starts tracking [pane] (an editor shown in the workspace).
  void attach(SplitPane pane) {
    _panes.add(pane);
    pane.session.content.lasso.dragOut = _DragOut(this, pane);
    void onTools() => _toolsChanged(pane);
    _toolListeners[pane] = onTools;
    pane.session.tools.addListener(onTools);
    // Both panes use the same tools: a pane opened next to another starts
    // with its tools.
    final other = _other(pane);
    if (other != null) pane.session.tools.adopt(other.session.tools);
  }

  /// Stops tracking [pane] (its editor went, or is leaving: see [_onTabs]).
  void detach(SplitPane pane) {
    if (!_panes.remove(pane)) return;
    pane.session.content.lasso.dragOut = null;
    final listener = _toolListeners.remove(pane);
    if (listener != null) pane.session.tools.removeListener(listener);
    if (_dropTarget == pane) _dropTarget = null;
    if (_dragSource == pane) _dragSource = null;
    if (_active == pane) _active = null;
    if (_solo == pane) {
      // The editor in focus mode went (its tab closed or switched, the split
      // closed): show the other pane again. Deferred, as editors detach
      // while the tree is locked (dispose).
      _solo = null;
      scheduleMicrotask(() {
        if (!_disposed) notifyListeners();
      });
    }
  }

  /// Records where the shown editors look, and their zoom windows, before
  /// the tabs change (a notebook may show in the first pane next).
  void _captureViews() {
    for (final pane in _panes) {
      if (pane.secondary) {
        if (pane.notebookId != tabs.splitId) continue;
        tabs.splitView = pane.session.viewState;
        // The first pane's zoom window wins when both show the notebook.
        if (pane.notebookId != tabs.activeId) pane.session.saveZoomState();
      } else if (pane.notebookId == tabs.activeId) {
        tabs.saveView(pane.notebookId, pane.session.viewState);
        pane.session.saveZoomState();
      }
    }
  }

  SplitPane? _other(SplitPane pane) => _panes.where((p) => p != pane).firstOrNull;

  /// Shows [message] in the pane other than [from] (e.g. why [from] is
  /// closing: its own messages would go with it). False if there is none.
  bool messageOther(SplitPane from, String message) {
    final other = _other(from);
    if (other == null) return false;
    other.showMessage(message);
    return true;
  }

  /// Shows [pane] alone (focus mode), or both again with null.
  void solo(SplitPane? pane) {
    if (_solo == pane) return;
    _solo = pane;
    notifyListeners();
  }

  void _onTabs() {
    // An editor whose notebook went from its place fades out for a moment
    // while the next one comes in: it is no longer part of the split (its
    // tools link to nothing, nothing drops into it).
    for (final pane in [..._panes]) {
      if (pane._showsIn(tabs)) continue;
      pane.onLeave?.call();
      detach(pane);
    }
    // Linked tools: the active editor's tools win.
    if (_panes.length == 2) {
      final primary = _panes.firstWhere((p) => !p.secondary, orElse: () => _panes.first);
      _other(primary)?.session.tools.adopt(primary.session.tools);
    }
  }

  // ---------------------------------------------------------------------------
  // Linked tools

  bool _adopting = false;

  void _toolsChanged(SplitPane pane) {
    if (_adopting) return;
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
