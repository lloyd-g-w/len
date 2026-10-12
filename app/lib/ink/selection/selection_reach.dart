import 'dart:ui';

import '../../domain/stroke.dart';
import '../../domain/surface_element.dart';
import '../geometry/affine.dart';
import '../surface_model.dart';
import 'lasso.dart';
import 'selection_surfaces.dart';
import 'transform_items.dart';

/// What a lasso selects on its surface and on the other surfaces it
/// reaches; items of other surfaces are moved into the lasso surface's
/// coordinates and come with their [sources].
typedef LassoPick = ({
  List<Stroke> strokes,
  List<SurfaceElement> elements,
  Map<String, SelectionSource> sources,
});

/// Selecting and hiding across the surfaces a selection reaches.
abstract final class SelectionReach {
  /// What [lasso] (in [model]'s coordinates) encloses on [model] and on the
  /// other [surfaces] it overlaps (the lasso moved into each).
  static LassoPick pick(SurfaceModel model, SelectionSurfaces? surfaces, Lasso lasso) {
    final strokes = [...model.strokesNear(lasso.bounds).where(lasso.selectsStroke)];
    final elements = [...model.elementsNear(lasso.bounds).where(lasso.selectsElement)];
    final sources = <String, SelectionSource>{};
    for (final other in surfaces?.near(model, lasso.bounds) ?? const <ShiftedSurface>[]) {
      final local = lasso.shifted(-other.shift);
      final there = other.model..ensureLoaded(local.bounds);
      final t = Affine.translation(other.shift);
      for (final s in there.strokesNear(local.bounds).where(local.selectsStroke)) {
        strokes.add(TransformItems.stroke(s, t, id: s.id));
        sources[s.id] = SelectionSource(other, s);
      }
      for (final e in there.elementsNear(local.bounds).where(local.selectsElement)) {
        elements.add(TransformItems.element(e, t));
        sources[e.id] = SelectionSource(other, e);
      }
    }
    return (strokes: strokes, elements: elements, sources: sources);
  }

  /// Hides the items [ids] on the surfaces holding them ([model], or the
  /// source's) for [owner], un-hides them on surfaces in [before] that no
  /// longer hold any, and returns the other surfaces now involved. Those
  /// surfaces start or stop being watched through [watch] / [unwatch].
  static Set<SurfaceModel> hide({
    required Object owner,
    required SurfaceModel model,
    required Iterable<String> ids,
    required Map<String, SelectionSource> sources,
    required Set<SurfaceModel> before,
    required VoidCallback onChanged,
  }) {
    final hidden = <SurfaceModel, Set<String>>{model: {}};
    for (final id in ids) {
      (hidden[sources[id]?.surface.model ?? model] ??= {}).add(id);
    }
    final others = {...hidden.keys}..remove(model);
    for (final gone in before.difference(others)) {
      gone
        ..removeListener(onChanged)
        ..setHidden(const {}, owner: owner);
    }
    for (final added in others.difference(before)) {
      added.addListener(onChanged);
    }
    hidden.forEach((m, ids) => m.setHidden(ids, owner: owner));
    return others;
  }
}
