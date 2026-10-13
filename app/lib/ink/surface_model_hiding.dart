part of 'surface_model.dart';

/// Content shown elsewhere while selected or edited: items hidden from the
/// committed ink layer, and what their owners draw in their place.
mixin _SurfaceHiding on _SurfaceState {
  bool isHidden(String id) => _hidden.contains(id);

  /// Whether some owner (a selection, a text editor) hides items here.
  bool get hasHidden => _hiddenBy.isNotEmpty;

  /// Replaces the stroke / element ids hidden by [owner] (e.g. a selection
  /// or a text editor). An item is hidden while any owner hides it, so two
  /// owners never un-hide each other's items.
  void setHidden(Set<String> ids, {Object? owner}) {
    if (_disposed) return;
    if (ids.isEmpty) {
      _hiddenBy.remove(owner);
    } else {
      _hiddenBy[owner] = ids;
    }
    final hidden = {for (final set in _hiddenBy.values) ...set};
    if (setEquals(hidden, _hidden)) return;
    final changed = <ChunkKey>{};
    final areas = <Rect>[];
    for (final id in {..._hidden, ...hidden}) {
      if (_hidden.contains(id) && hidden.contains(id)) continue;
      final stroke = _strokes[id];
      final element = _elements[id];
      if (stroke != null) {
        changed.addAll(StrokeChunks.of(stroke));
        areas.add(stroke.bounds);
      }
      if (element != null) {
        changed.addAll(ElementChunks.of(element));
        areas.add(element.bounds);
      }
    }
    _hidden = Set.unmodifiable(hidden);
    _changed(changed, areas: areas);
  }

  /// Notifies when lifted content appears, changes or goes.
  Listenable get liftedChanges => _lifted;

  /// Sets (or with null, removes) what [owner] draws in place of the items
  /// it hides; other views of this surface paint it ([paintLifted]) instead
  /// of showing a hole.
  void setLifted(Object owner, LiftedPaint? paint) {
    // A selection or text session outliving the model (disposed later in
    // teardown) lets go of nothing that still draws.
    if (!_disposed) _lifted.set(owner, paint);
  }

  /// [owner]'s lifted content changed (it moved, was retyped).
  void liftedChanged(Object owner) {
    if (!_disposed) _lifted.changed(owner);
  }

  /// Whose lifted content changed last (see [ForeignLiftedChanges]).
  Object? get lastLiftedOwner => _lifted.lastOwner;

  /// Whether owners other than [except] have lifted content here.
  bool hasLiftedExcept(Set<Object?> except) => _lifted.hasExcept(except);

  /// Paints the lifted content of owners other than [except] (in this
  /// surface's coordinates).
  void paintLifted(Canvas canvas, {Set<Object?> except = const {}}) =>
      _lifted.paint(canvas, except: except);
}
