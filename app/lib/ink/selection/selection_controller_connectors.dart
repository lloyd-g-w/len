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
    final selected = {for (final s in _strokes) s.shapeId};
    // Shapes replaced on the surface they were on: shape id → new stroke.
    final replaced = <String, Stroke>{};
    final identified = [
      for (var i = 0; i < strokes.length; i++)
        i < _strokes.length ? _identified(_strokes[i], strokes[i], surfaceOf(i)) : strokes[i],
    ];
    for (var i = 0; i < _strokes.length && i < identified.length; i++) {
      final old = _strokes[i], now = identified[i];
      if (!ShapeAnchors.isTarget(old.shape) || !ShapeAnchors.isTarget(now.shape)) continue;
      if (now.shapeId == old.shapeId) replaced[old.shapeId] = now;
    }
    final out = [
      for (var i = 0; i < identified.length; i++)
        (identified[i].shape?.isAttached ?? false) && i < _strokes.length
            ? _attachedSelected(identified[i], _sourceOf(_strokes[i]), selected, replaced)
            : identified[i],
    ];
    if (replaced.isNotEmpty) _follow(plan, replaced);
    return out;
  }

  /// [now], the edit of shape [old] going to surface [to], with [old]'s
  /// identity ([Stroke.shapeId]) when it stays on its surface; moved to
  /// another, it is a shape of its own there.
  Stroke _identified(Stroke old, Stroke now, SurfaceModel to) {
    final shape = now.shape;
    if (shape == null || old.shape == null || now.id == old.id) return now;
    final origin = to == _sourceOf(old).model ? old.shapeId : null;
    return shape.origin == origin
        ? now
        : now.withPoints(now.points, shape: shape.withOrigin(origin));
  }

  ShiftedSurface _sourceOf(Stroke s) =>
      _sources[s.id]?.surface ?? (model: _model, shift: Offset.zero);

  /// Selected line [s] (stored on [source]) with each end attached to a
  /// shape edited with it (among the [selected] shape ids; kept when it
  /// stays on its surface), or to another it still sits on; else let go.
  Stroke _attachedSelected(
    Stroke s,
    ShiftedSurface source,
    Set<String> selected,
    Map<String, Stroke> replaced,
  ) {
    final line = s.shape!;
    // Where its ends are stored.
    final stored = line.map((p) => p - source.shift);
    ShapeAttachment? kept(int end) {
      final a = line.attachmentOf(end);
      if (a == null) return null;
      if (selected.contains(a.id)) return replaced.containsKey(a.id) ? a : null;
      final near = Rect.fromCircle(center: stored.points[end], radius: 1);
      final target = Connectors.targetOf(stored, end, source.model.strokesNear(near));
      return Connectors.sits(stored, end, target?.shape) ? a : null;
    }

    final shape = ShapeGeometry(
      line.kind,
      line.points,
      tail: kept(0),
      tip: kept(1),
      origin: line.origin,
    );
    return shape == line ? s : s.withPoints(s.points, shape: shape);
  }

  /// Adds to [plan] the unselected lines attached to the [replaced] shapes,
  /// following them.
  void _follow(SelectionPlan plan, Map<String, Stroke> replaced) {
    for (final (model, line, shape) in _followersOf(replaced)) {
      plan.replaceUnselected(model, line, Connectors.rebuilt(line, shape, id: clock.newId()));
    }
  }

  /// The unselected lines attached to the [replaced] shapes (by shape id),
  /// where they are stored, and their geometry following the shapes (in
  /// that surface's coordinates). With [homeOnly], only lines on this
  /// surface. A line attached to another stroke of the same shape (a copy
  /// left by edits on two devices at once, near its end) stays.
  List<(SurfaceModel, Stroke, ShapeGeometry)> _followersOf(
    Map<String, Stroke> replaced, {
    bool homeOnly = false,
  }) {
    final selected = {for (final s in _strokes) s.id};
    final lines = <String, (SurfaceModel, Stroke, ShapeGeometry)>{};
    for (final MapEntry(key: id, value: now) in replaced.entries) {
      final old = _strokes.firstWhere((s) => s.shapeId == id);
      final surface = _sourceOf(old);
      if (homeOnly && surface.model != _model) continue;
      final stored = (_sources[old.id]?.original as Stroke?) ?? old;
      final target = {id: now.shape!.map((p) => p - surface.shift)};
      final attached = [
        for (final s in surface.model.strokesNear(stored.bounds))
          if (!selected.contains(s.id) && _attachedTo(s.shape, id)) s,
      ];
      if (attached.isEmpty) continue;
      final copies = _copiesNear(surface.model, stored, attached);
      bool follows(ShapeGeometry line, int end) {
        if (line.attachmentOf(end)?.id != id) return false;
        final near = Rect.fromCircle(center: line.points[end], radius: 1);
        final named = [stored, ...copies.where((c) => c.bounds.overlaps(near))];
        return Connectors.targetOf(line, end, named)?.id == stored.id;
      }

      for (final s in attached) {
        final shape = lines[s.id]?.$3 ?? s.shape!;
        if (!follows(s.shape!, 0) && !follows(s.shape!, 1)) continue;
        lines[s.id] = (surface.model, s, Connectors.follow(shape, target));
      }
    }
    return lines.values.toList();
  }

  /// Whether an end of [line] is attached to shape [id].
  static bool _attachedTo(ShapeGeometry? line, String id) =>
      line != null && (line.tail?.id == id || line.tip?.id == id);

  /// The other strokes of [shape]'s shape id on [model] near the ends of
  /// [lines] attached to it: one query for all of them (a query per end
  /// was most of a move's time with many lines).
  static List<Stroke> _copiesNear(SurfaceModel model, Stroke shape, List<Stroke> lines) {
    final id = shape.shapeId;
    Rect? ends;
    for (final line in lines) {
      for (final end in [0, 1]) {
        if (line.shape!.attachmentOf(end)?.id != id) continue;
        final near = Rect.fromCircle(center: line.shape!.points[end], radius: 1);
        ends = ends?.expandToInclude(near) ?? near;
      }
    }
    return [
      for (final s in model.strokesNear(ends!))
        if (s.shapeId == id && s.id != shape.id) s,
    ];
  }

  /// Shows the unselected lines attached to [replaced] shapes (selected
  /// ones as a gesture would leave them) following them, in place of their
  /// stored selves.
  void _previewFollowers(Map<String, Stroke> replaced) {
    final lines = replaced.isEmpty
        ? const <(SurfaceModel, Stroke, ShapeGeometry)>[]
        : _followersOf(replaced, homeOnly: true);
    if (lines.isEmpty && _followers == null) return;
    _followers?.dispose();
    _followers = lines.isEmpty
        ? null
        : _recordSketch([
            for (final (_, line, shape) in lines) Connectors.rebuilt(line, shape, id: line.id),
          ]);
    final ids = {for (final (_, line, _) in lines) line.id};
    if (!setEquals(ids, _followerIds)) {
      _followerIds = ids;
      _hide();
    }
  }

  /// The selected shapes as [t] would move them (their geometry only), by
  /// shape id.
  Map<String, Stroke> _moved(Affine t) => {
    for (final s in _strokes)
      if (ShapeAnchors.isTarget(s.shape))
        s.shapeId: s.withPoints(s.points, shape: s.shape!.map(t.apply)),
  };

  /// Pasted copies [strokes] of [originals] (in order): shapes of their
  /// own ([Stroke.shapeId] their new ids), attached to each other's
  /// copies; ends attached to shapes not pasted with them let go.
  static List<Stroke> _pastedConnectors(List<Stroke> originals, List<Stroke> strokes) {
    final ids = {for (var i = 0; i < strokes.length; i++) originals[i].shapeId: strokes[i].id};
    return [
      for (final s in strokes)
        if (s.shape case final shape?)
          s.withPoints(
            s.points,
            shape: shape
                .withOrigin(null)
                .withAttachments((a) => ids[a.id] == null ? null : a.withId(ids[a.id]!)),
          )
        else
          s,
    ];
  }
}
