import 'dart:ui';

import '../../../ink/surface_model.dart';
import '../editor_session.dart';

/// Where focus mode's puck goes when it is released over ink: the spot
/// nearest the release, along the edges, with no ink under it.
abstract final class PuckClearance {
  /// Spots along the edges, as fractions of the free area (a side spot
  /// runs the puck down that side, see `ToolbarSlot.isVertical`).
  static const List<(double, double)> spots = [
    (0.5, 1),
    (0.25, 1),
    (0.75, 1),
    (0.5, 0),
    (0.25, 0),
    (0.75, 0),
    (0, 0.5),
    (1, 0.5),
    (0, 0.25),
    (1, 0.25),
    (0, 0.75),
    (1, 0.75),
  ];

  /// Where a puck released at [at] (fractions of the free area) settles:
  /// [at] itself when [blocked] says nothing is under it there, else the
  /// clear spot (of [spots]) nearest to it, else [at]. [rectAt] gives the
  /// puck's rectangle at a position.
  static (double, double) settle(
    (double, double) at, {
    required Rect Function((double, double) at) rectAt,
    required bool Function(Rect rect) blocked,
  }) {
    if (!blocked(rectAt(at))) return at;
    final from = rectAt(at).center;
    (double, double)? best;
    var bestDistance = double.infinity;
    for (final spot in spots) {
      final rect = rectAt(spot);
      if (blocked(rect)) continue;
      final distance = (rect.center - from).distanceSquared;
      if (distance < bestDistance) {
        best = spot;
        bestDistance = distance;
      }
    }
    return best ?? at;
  }

  /// Whether ink, text or an image of [session] lies under [screen] (a
  /// rectangle in the editor's coordinates).
  static bool inkUnder(EditorSession session, Rect screen) {
    final doc = session.doc;
    if (doc == null) {
      final model = session.canvas, viewport = session.canvasViewport;
      if (model == null || viewport == null) return false;
      return _overlaps(
        model,
        Rect.fromPoints(viewport.toWorld(screen.topLeft), viewport.toWorld(screen.bottomRight)),
      );
    }
    final viewport = doc.viewport;
    final world = Rect.fromPoints(
      viewport.toWorld(screen.topLeft),
      viewport.toWorld(screen.bottomRight),
    );
    for (final index in doc.layout.visiblePages(world)) {
      final frame = doc.layout.frameOf(index)!;
      final surface = doc.surfaces.peek(doc.pages[index].id);
      if (surface == null) continue;
      if (_overlaps(surface.model, world.shift(-frame.topLeft))) return true;
    }
    return false;
  }

  static bool _overlaps(SurfaceModel model, Rect world) =>
      model.strokesNear(world).any((s) => s.bounds.overlaps(world)) ||
      model.elementsNear(world).isNotEmpty;
}
