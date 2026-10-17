part of 'selection_controller.dart';

/// Connectors in selection edits ([Connectors]): lines and arrows attached
/// to an edited shape follow it in the same commit; a selected line's end
/// stays attached only to a shape edited with it, or to one it still sits
/// on (recoloured, bent), and lets go when moved without it.
extension _SelectionConnectors on _SelectionCore {
  /// [strokes] (replacing the selected ones, in order) with their
  /// attachments brought up to date, and the unselected lines attached to
  /// replaced shapes following them in [plan]. [surfaceOf] tells the
  /// surface stroke `i` goes to.
  List<Stroke> _connect(
    List<Stroke> strokes,
    SelectionPlan plan,
    SurfaceModel Function(int i) surfaceOf,
  ) {
    final selected = {for (final s in _strokes) s.id};
    // Shapes replaced on the surface they were on: old id → new stroke.
    final replaced = <String, Stroke>{};
    for (var i = 0; i < _strokes.length && i < strokes.length; i++) {
      final old = _strokes[i], now = strokes[i];
      if (!ShapeAnchors.isTarget(old.shape) || !ShapeAnchors.isTarget(now.shape)) continue;
      if (surfaceOf(i) != _sourceOf(old).model) continue;
      replaced[old.id] = now;
    }
    final out = [
      for (var i = 0; i < strokes.length; i++)
        (strokes[i].shape?.isAttached ?? false) && i < _strokes.length
            ? _attachedSelected(strokes[i], _sourceOf(_strokes[i]), selected, replaced)
            : strokes[i],
    ];
    if (replaced.isNotEmpty) _follow(plan, replaced, selected);
    return out;
  }

  ShiftedSurface _sourceOf(Stroke s) =>
      _sources[s.id]?.surface ?? (model: _model, shift: Offset.zero);

  /// Selected line [s] (stored on [source]) with each end attached to a
  /// shape edited with it (by its new id), or to another it still sits on;
  /// else let go.
  Stroke _attachedSelected(
    Stroke s,
    ShiftedSurface source,
    Set<String> selected,
    Map<String, Stroke> replaced,
  ) {
    final line = s.shape!;
    ShapeAttachment? kept(int end) {
      final a = line.attachmentOf(end);
      if (a == null) return null;
      if (selected.contains(a.id)) {
        final now = replaced[a.id];
        return now == null ? null : a.withId(now.id);
      }
      // Its target where it is stored, in selection coordinates.
      final target = source.model.strokeById(a.id)?.shape?.map((p) => p + source.shift);
      return Connectors.sits(line, end, target) ? a : null;
    }

    final shape = ShapeGeometry(line.kind, line.points, tail: kept(0), tip: kept(1));
    return shape == line ? s : s.withPoints(s.points, shape: shape);
  }

  /// Adds to [plan] the unselected lines attached to the [replaced] shapes,
  /// following them.
  void _follow(SelectionPlan plan, Map<String, Stroke> replaced, Set<String> selected) {
    final lines = <String, (SurfaceModel, Stroke, ShapeGeometry)>{};
    final targets = <SurfaceModel, Map<String, Followed>>{};
    for (final MapEntry(key: id, value: now) in replaced.entries) {
      final old = _strokes.firstWhere((s) => s.id == id);
      final surface = _sourceOf(old);
      final stored = (_sources[id]?.original as Stroke?) ?? old;
      final shift = surface.shift;
      (targets[surface.model] ??= {})[id] = (id: now.id, shape: now.shape!.map((p) => p - shift));
      for (final s in surface.model.strokesNear(stored.bounds)) {
        final shape = s.shape;
        if (shape == null || selected.contains(s.id) || lines.containsKey(s.id)) continue;
        if (shape.tail?.id != id && shape.tip?.id != id) continue;
        lines[s.id] = (surface.model, s, shape);
      }
    }
    for (final (model, line, shape) in lines.values) {
      final followed = Connectors.follow(shape, targets[model]!);
      plan.replaceUnselected(model, line, Connectors.rebuilt(line, followed, id: clock.newId()));
    }
  }

  /// Pasted copies [strokes] of [originals] (in order) attached to each
  /// other's copies; ends attached to shapes not pasted with them let go.
  static List<Stroke> _pastedConnectors(List<Stroke> originals, List<Stroke> strokes) {
    final ids = {for (var i = 0; i < strokes.length; i++) originals[i].id: strokes[i].id};
    return [
      for (final s in strokes)
        if (s.shape?.isAttached ?? false)
          s.withPoints(
            s.points,
            shape: s.shape!.withAttachments((a) => ids[a.id] == null ? null : a.withId(ids[a.id]!)),
          )
        else
          s,
    ];
  }
}
