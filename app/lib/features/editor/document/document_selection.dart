import 'dart:ui';

import '../../../ink/selection/selection_surfaces.dart';
import '../../../ink/surface_model.dart';
import 'document_controller.dart';

/// The pages of a paged notebook as seen by a lasso selection on one of
/// them: a lasso drawn across pages selects on each (the lasso is moved
/// into each page's coordinates), items dropped onto another page move
/// there, and edits spanning pages are one notebook-wide undo step.
///
/// Pages are found in the document layout, so in single-page flow (one
/// page laid out) a selection stays on its page.
class DocumentSelection implements SelectionSurfaces {
  DocumentSelection(this.doc);

  final DocumentController doc;

  /// Document-space frame of the page shown by [model], if laid out.
  Rect? _frameOf(SurfaceModel model) {
    final index = doc.pages.indexWhere((p) => p.id == model.surfaceId);
    return index == -1 ? null : doc.layout.frameOf(index);
  }

  ShiftedSurface _surface(int index, Offset origin) => (
    model: doc.surfaces.surfaceOf(doc.pages[index].id).model,
    shift: doc.layout.frameOf(index)!.topLeft - origin,
  );

  @override
  Iterable<ShiftedSurface> near(SurfaceModel from, Rect area) {
    final frame = _frameOf(from);
    if (frame == null) return const [];
    return [
      for (final index in doc.layout.visiblePages(area.shift(frame.topLeft)))
        if (doc.pages[index].id != from.surfaceId) _surface(index, frame.topLeft),
    ];
  }

  @override
  ShiftedSurface? at(SurfaceModel from, Offset point) {
    final frame = _frameOf(from);
    if (frame == null) return null;
    final index = doc.layout.pageAt(point + frame.topLeft);
    if (index == null) return null;
    if (doc.pages[index].id == from.surfaceId) return (model: from, shift: Offset.zero);
    return _surface(index, frame.topLeft);
  }

  @override
  void batch(void Function() edits) => doc.surfaces.models.group(edits);
}
