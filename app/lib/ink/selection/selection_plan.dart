import 'dart:ui';

import '../../domain/stroke.dart';
import '../../domain/surface_element.dart';
import '../surface_model.dart';
import '../undo_history.dart';
import 'selection_surfaces.dart';

/// The edits of one selection change, possibly spread over several
/// surfaces (pages): which stored items go, which come (in each surface's
/// own coordinates) and what the selection holds afterwards (in the
/// selection's coordinates, with the [sources] of items on other surfaces).
///
/// Items are given in the selection's coordinates; [add] converts them into
/// the target surface's. An element moving to another surface keeps its id:
/// it is removed from its old surface before it is saved on the new one
/// (every removal is committed before any arrival), so storage and sync
/// see it re-parented, and undo (in reverse order) puts it back.
class SelectionPlan {
  SelectionPlan(this.primary);

  /// The selection's own surface.
  final SurfaceModel primary;

  late final ShiftedSurface _home = (model: primary, shift: Offset.zero);

  final Map<SurfaceModel, _Edit> _first = {};
  final Map<SurfaceModel, _Edit> _arrivals = {};

  /// The selection after the change (selection coordinates).
  final List<Stroke> strokes = [];
  final List<SurfaceElement> elements = [];
  final Map<String, SelectionSource> sources = {};

  ShiftedSurface _surfaceOf(SelectionSource? source) => source?.surface ?? _home;

  /// Removes stored stroke [s] (selection coordinates), from [source].
  void removeStroke(Stroke s, SelectionSource? source) {
    final surface = _surfaceOf(source);
    _edit(_first, surface.model).removed.add((source?.original as Stroke?) ?? s);
  }

  /// Removes stored element [e] (selection coordinates), from [source].
  void removeElement(SurfaceElement e, SelectionSource? source) {
    final surface = _surfaceOf(source);
    _edit(_first, surface.model).removedElements.add((source?.original as SurfaceElement?) ?? e);
  }

  /// Keeps stroke [s] selected as it is.
  void keepStroke(Stroke s, SelectionSource? source) {
    strokes.add(s);
    if (source != null) sources[s.id] = source;
  }

  /// Keeps element [e] selected as it is.
  void keepElement(SurfaceElement e, SelectionSource? source) {
    elements.add(e);
    if (source != null) sources[e.id] = source;
  }

  /// Adds stroke [s] (selection coordinates) to surface [to] (default: the
  /// selection's own) and selects it.
  void addStroke(Stroke s, {ShiftedSurface? to}) {
    final target = to ?? _home;
    final stored = _strokeOn(s, target);
    _edit(_first, target.model).added.add(stored);
    final selected = target.model == primary
        ? stored
        : _strokeOn(s, (model: target.model, shift: Offset.zero));
    keepStroke(selected, target.model == primary ? null : SelectionSource(target, stored));
  }

  /// Adds element [e] (selection coordinates) to surface [to] (default: the
  /// selection's own) and selects it. [from] is the surface it was stored
  /// on, if it replaces a stored element with the same id.
  void addElement(SurfaceElement e, {ShiftedSurface? to, SelectionSource? from}) {
    final target = to ?? _home;
    final home = target.model == primary;
    final id = target.model.surfaceId;
    final stored = home && e.surfaceId == id
        ? e
        : e.copyWith(rect: e.rect.shift(-target.shift), surfaceId: id);
    final moving = _surfaceOf(from).model != target.model;
    _edit(moving ? _arrivals : _first, target.model).addedElements.add(stored);
    keepElement(
      home ? stored : e.copyWith(surfaceId: id),
      home ? null : SelectionSource(target, stored),
    );
  }

  /// Commits every surface's edits; through [batch] (one undo step) when
  /// more than one commit is needed. With [mergeInto], a change that only
  /// edits that surface joins its previous undo step (a burst of nudges).
  /// Returns the surface when only one was edited.
  SurfaceModel? commit(void Function(void Function() edits) batch, {SurfaceModel? mergeInto}) {
    final edits = [
      for (final e in _first.entries) (e.key, e.value.build()),
      for (final e in _arrivals.entries) (e.key, e.value.build()),
    ].where((e) => !e.$2.isEmpty).toList();
    final merge = edits.length == 1 && edits.single.$1 == mergeInto;
    void run() {
      for (final (model, edit) in edits) {
        model.commit(edit, merge: merge);
      }
    }

    edits.length > 1 ? batch(run) : run();
    return edits.length == 1 ? edits.single.$1 : null;
  }

  static _Edit _edit(Map<SurfaceModel, _Edit> edits, SurfaceModel model) =>
      edits[model] ??= _Edit();

  /// [s] (selection coordinates) as stored on [target].
  static Stroke _strokeOn(Stroke s, ShiftedSurface target) {
    final id = target.model.surfaceId;
    if (target.shift == Offset.zero && s.surfaceId == id) return s;
    final d = -target.shift;
    return Stroke(
      id: s.id,
      surfaceId: id,
      tool: s.tool,
      color: s.color,
      width: s.width,
      points: [for (final p in s.points) StrokePoint(p.x + d.dx, p.y + d.dy, p.pressure)],
      createdAt: s.createdAt,
      style: s.style,
    );
  }
}

class _Edit {
  final List<Stroke> added = [];
  final List<Stroke> removed = [];
  final List<SurfaceElement> addedElements = [];
  final List<SurfaceElement> removedElements = [];

  InkEdit build() => InkEdit(
    added: added,
    removed: removed,
    addedElements: addedElements,
    removedElements: removedElements,
  );
}
