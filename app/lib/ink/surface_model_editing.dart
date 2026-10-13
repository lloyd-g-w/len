part of 'surface_model.dart';

/// Undoable edits: applied to the working set, written to storage (right
/// away or, with [_SurfaceState.writeBehind], after the frame showing them)
/// and recorded in the undo history.
mixin _SurfaceEditing on _SurfaceState {
  /// Adds a newly drawn stroke (persisted immediately, undoable).
  void addStroke(Stroke stroke) => commit(InkEdit(added: [stroke]));

  /// Applies [edit] (persisted immediately) and records it for undo. With
  /// [merge], it joins the previous undo step (one continuous gesture).
  ///
  /// Ignored once disposed (its page is gone): nothing is written to it.
  void commit(InkEdit edit, {bool merge = false}) {
    if (edit.isEmpty || _disposed) return;
    _apply(edit);
    history.record(edit, merge: merge);
    onCommit?.call();
  }

  /// Erases along the eraser sweep from [a] to [b]: in [EraserMode.stroke]
  /// every touched stroke is removed; in [EraserMode.pixel] only the ink
  /// under the eraser is, and the surviving parts are added as new strokes.
  /// With [highlighterOnly], pen ink is left alone.
  ///
  /// Consecutive calls with [continueEdit] merge into one undo step.
  /// Returns whether anything was erased.
  bool eraseAlong(
    Offset a,
    Offset b,
    double radius, {
    required bool continueEdit,
    EraserMode mode = EraserMode.stroke,
    bool highlighterOnly = false,
  }) {
    final sweep = Rect.fromPoints(a, b).inflate(radius);
    final removed = <Stroke>[];
    final added = <Stroke>[];
    for (final stroke in _strokes.query(sweep)) {
      if (highlighterOnly && !stroke.tool.isHighlighter) continue;
      if (_hidden.contains(stroke.id)) continue;
      if (mode == EraserMode.stroke) {
        if (StrokeHitTest.sweepHits(stroke, a, b, radius)) removed.add(stroke);
        continue;
      }
      final fragments = StrokeSplitter.erase(stroke, a, b, radius, newId: clock.newId);
      if (fragments == null) continue;
      removed.add(stroke);
      added.addAll(fragments);
    }
    if (removed.isEmpty) return false;
    commit(
      InkEdit(added: added, removed: removed),
      merge: continueEdit,
    );
    return true;
  }

  /// Scribble to erase: removes the strokes the scribble [path] (world)
  /// crosses, within [radius], that lie mostly inside its bounds (so a long
  /// line under a scribbled word stays), as one undoable edit. Returns how
  /// many strokes went.
  int eraseScribbled(List<Offset> path, double radius) {
    if (path.length < 2) return 0;
    var area = Rect.fromPoints(path.first, path.first);
    for (final p in path) {
      area = area.expandToInclude(Rect.fromPoints(p, p));
    }
    area = area.inflate(radius);
    final box = Lasso([area.topLeft, area.topRight, area.bottomRight, area.bottomLeft]);
    bool crossed(Stroke stroke) {
      for (var i = 1; i < path.length; i++) {
        if (StrokeHitTest.sweepHits(stroke, path[i - 1], path[i], radius)) return true;
      }
      return false;
    }

    final removed = [
      for (final stroke in _strokes.query(area))
        if (!_hidden.contains(stroke.id) &&
            box.insideShare(stroke) >= Lasso.strokeShare &&
            crossed(stroke))
          stroke,
    ];
    commit(InkEdit(removed: removed));
    return removed.length;
  }

  void undo() {
    if (_disposed) return;
    final edit = history.takeUndo();
    if (edit != null) _apply(edit.inverse);
  }

  void redo() {
    if (_disposed) return;
    final edit = history.takeRedo();
    if (edit != null) _apply(edit);
  }

  void _apply(InkEdit edit) {
    final changed = <ChunkKey>{};

    if (edit.removed.isNotEmpty || edit.added.isNotEmpty) {
      if (writeBehind) {
        _unsaved.add(edit);
        if (_withUnsaved.add(this)) {
          // After the frame that shows the edit is handed to the raster
          // thread, so the write runs alongside its rasterisation.
          SchedulerBinding.instance
            ..addPostFrameCallback((_) => flush())
            ..ensureVisualUpdate();
        }
      } else {
        _write(edit);
      }
    }
    if (_preparing > 0) {
      _removedWhilePreparing
        ..addAll(edit.removed.map((s) => s.id))
        ..addAll(edit.removedElements.map((e) => e.id));
    }
    final areas = <Rect>[];
    for (final s in edit.removed) {
      final current = _strokes[s.id];
      if (current != null) _removeStroke(current);
      changed.addAll(StrokeChunks.of(s));
      areas.add(s.bounds);
    }
    final appended = _isAppend(edit);
    for (final s in edit.added) {
      _strokes.insert(s);
      changed.addAll(StrokeChunks.of(s));
      areas.add(s.bounds);
    }

    // An element replaced by a new value keeps its id: only delete the
    // ones that are not re-added.
    final keptIds = {for (final e in edit.addedElements) e.id};
    final deleted = [
      for (final e in edit.removedElements)
        if (!keptIds.contains(e.id)) e.id,
    ];
    if (deleted.isNotEmpty) _elementRepository?.delete(deleted);
    if (edit.addedElements.isNotEmpty) _elementRepository?.save(edit.addedElements);
    for (final e in edit.removedElements) {
      final current = _elements[e.id];
      if (current != null) {
        _removeElement(current);
        changed.addAll(ElementChunks.of(current));
        areas.add(current.bounds);
      }
      changed.addAll(ElementChunks.of(e));
      areas.add(e.bounds);
    }
    for (final e in edit.addedElements) {
      _elements.insert(e);
      changed.addAll(ElementChunks.of(e));
      areas.add(e.bounds);
    }
    _changed(changed, appended: appended ? edit.added : null, areas: areas);
  }

  /// Whether [edit] only adds pen strokes painted over everything already
  /// in their chunks (nothing above the ink there, nothing hidden), so
  /// drawing them over a rendering of the chunks before the edit gives the
  /// rendering after it. Checked before the strokes are inserted.
  bool _isAppend(InkEdit edit) {
    if (edit.added.isEmpty || edit.removed.isNotEmpty) return false;
    if (edit.addedElements.isNotEmpty || edit.removedElements.isNotEmpty) return false;
    for (final s in edit.added) {
      if (s.tool.isHighlighter || _strokes.containsId(s.id) || _hidden.contains(s.id)) {
        return false;
      }
      for (final key in StrokeChunks.of(s)) {
        for (final other in _strokes.inChunk(key)) {
          if (Stroke.paintOrder(other, s) > 0) return false;
        }
        if (_elements.inChunk(key).any((e) => !e.belowInk)) return false;
      }
    }
    return true;
  }

  /// Writes stroke edits still waiting for [writeBehind] to storage.
  @override
  void flush() {
    _withUnsaved.remove(this);
    if (_unsaved.isEmpty) return;
    final edits = List.of(_unsaved);
    _unsaved.clear();
    edits.forEach(_write);
  }

  void _write(InkEdit edit) {
    developer.Timeline.startSync('len.persistStrokes');
    if (edit.removed.isNotEmpty) _repository.delete(edit.removed.map((s) => s.id));
    if (edit.added.isNotEmpty) _repository.save(edit.added);
    developer.Timeline.finishSync();
  }

  /// Marks [chunks] for re-rendering although no content changed (e.g. an
  /// image in them finished decoding).
  void refresh(Set<ChunkKey> chunks) {
    if (chunks.isNotEmpty) _changed(chunks);
  }
}
