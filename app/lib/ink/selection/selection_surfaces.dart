import 'dart:ui';

import '../surface_model.dart';

/// Another surface seen from the selection's own surface: a point on
/// [model] plus [shift] is the same point in the selection's coordinates
/// (for pages of a document: the other page's origin minus the selection
/// page's origin).
typedef ShiftedSurface = ({SurfaceModel model, Offset shift});

/// The surfaces next to a selection's own one that it may reach: the other
/// pages of a paged notebook, so a lasso drawn across pages selects on each
/// and a selection dropped on another page moves there. Positions and
/// areas are in the coordinates of the selection's surface ([from]).
abstract interface class SelectionSurfaces {
  /// Surfaces other than [from] whose pages overlap [area].
  Iterable<ShiftedSurface> near(SurfaceModel from, Rect area);

  /// The surface whose page contains [point] (possibly [from] itself, with
  /// a zero shift), or null when the point is on no page.
  ShiftedSurface? at(SurfaceModel from, Offset point);

  /// Runs [edits] (commits on several surfaces) as one undo step.
  void batch(void Function() edits);
}

/// Where a selected item lives when it is not on the selection's own
/// surface: its [surface] and its stored value there ([original], in that
/// surface's coordinates; the selection holds a copy moved by the shift).
class SelectionSource {
  const SelectionSource(this.surface, this.original);

  final ShiftedSurface surface;
  final Object original;
}
