import 'package:flutter/widgets.dart';

import '../../domain/notebook.dart';
import '../editor/tabs/notebook_open_route.dart';
import 'notebook_cover.dart';
import 'thumbnails/thumbnail_scope.dart';

/// Finds notebook covers on screen by notebook id, so a notebook opens out
/// of its cover and closes back into it, even if the library re-sorted
/// (and rebuilt the card) meanwhile.
class CoverLocator {
  final Map<String, BuildContext> _covers = {};

  /// The on-screen rect of [notebookId]'s cover in global coordinates, or
  /// null when it is not shown.
  Rect? rectOf(String notebookId) {
    final context = _covers[notebookId];
    if (context == null || !context.mounted) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);
  }

  /// Where [notebook] opens from, if its cover is shown; [context] is any
  /// context under the library's thumbnail scope (for the live preview).
  NotebookOpenOrigin? originOf(BuildContext context, Notebook notebook) {
    final rect = rectOf(notebook.id);
    if (rect == null) return null;
    // The route owns a clone: the cache may replace the preview mid-flight.
    final scope = context.getInheritedWidgetOfExactType<ThumbnailScope>();
    final preview = scope?.notifier?.imageFor(notebook)?.clone();
    return NotebookOpenOrigin(
      rect: rect,
      cover: NotebookCover(
        color: notebook.coverColor,
        kind: notebook.kind,
        favorite: notebook.favorite,
        preview: preview,
      ),
      paper: notebook.paperColor.paper,
      locate: () => rectOf(notebook.id),
      dispose: preview?.dispose,
    );
  }
}

/// Registers its child as [notebookId]'s cover with [locator].
class CoverAnchor extends StatefulWidget {
  const CoverAnchor({
    super.key,
    required this.locator,
    required this.notebookId,
    required this.child,
  });

  final CoverLocator locator;
  final String notebookId;
  final Widget child;

  @override
  State<CoverAnchor> createState() => _CoverAnchorState();
}

class _CoverAnchorState extends State<CoverAnchor> {
  @override
  void initState() {
    super.initState();
    widget.locator._covers[widget.notebookId] = context;
  }

  @override
  void didUpdateWidget(CoverAnchor old) {
    super.didUpdateWidget(old);
    _forget(old);
    widget.locator._covers[widget.notebookId] = context;
  }

  @override
  void dispose() {
    _forget(widget);
    super.dispose();
  }

  void _forget(CoverAnchor w) {
    if (identical(w.locator._covers[w.notebookId], context)) w.locator._covers.remove(w.notebookId);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
