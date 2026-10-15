part of 'split_controller.dart';

/// One editor of the split view, as the [SplitController] sees it.
class SplitPane {
  SplitPane({
    required this.session,
    required this.secondary,
    required this.area,
    required this.showMessage,
    this.onLeave,
  });

  final EditorSession session;

  /// The second (right) pane.
  final bool secondary;

  /// The editor's area (its surface's coordinate space).
  final RenderBox? Function() area;

  /// Shows a message (snack bar) in this pane.
  final ValueChanged<String> showMessage;

  /// The tabs moved this pane's notebook away (it fades out next): puts
  /// back what the editor changed in the shared tools for the moment (the
  /// laser of focus mode), while they are still linked.
  final VoidCallback? onLeave;

  /// Whether the tabs still show this pane's notebook in its place.
  bool _showsIn(OpenNotebooks tabs) => notebookId == (secondary ? tabs.splitId : tabs.activeId);

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
