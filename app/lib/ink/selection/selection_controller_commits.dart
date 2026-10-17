part of 'selection_controller.dart';

/// Turning edits of the selection into one undoable commit: pasting, replacing
/// the selected items (on the surfaces they belong to) and selecting the result.
extension _SelectionCommits on _SelectionCore {
  void _paste(List<Stroke> strokes, List<SurfaceElement> elements, Rect bounds, Offset at) {
    final t = Affine.translation(at - bounds.center);
    final now = clock.nowMs();
    final ordered = [...strokes]..sort(Stroke.paintOrder);
    final orderedElements = [...elements]..sort(SurfaceElement.paintOrder);
    final z = ElementOrder.pasted(
      orderedElements,
      top: _model.topZ,
      topBelowInk: _model.topBelowInkZ,
    );
    final newStrokes = _SelectionConnectors._pastedConnectors(ordered, [
      for (var i = 0; i < ordered.length; i++)
        _onSurface(TransformItems.stroke(ordered[i], t, id: clock.newId()), now + i),
    ]);
    final newElements = [
      for (var i = 0; i < orderedElements.length; i++)
        TransformItems.element(
          orderedElements[i],
          t,
        ).copyWith(id: clock.newId(), surfaceId: _model.surfaceId, z: z[i], createdAt: now),
    ];
    final plan = SelectionPlan(_model);
    for (final s in newStrokes) {
      plan.addStroke(s, to: _target(s.bounds.center, null, transfer: true));
    }
    for (final e in newElements) {
      plan.addElement(e, to: _target(_anchorOf(e), null, transfer: true));
    }
    _apply(plan);
  }

  /// The point deciding the page a pasted element goes to: its centre; a
  /// text box's top, where its text begins (a box flowing across pages
  /// comes with its whole text, maybe pages tall, and flows on from there).
  static Offset _anchorOf(SurfaceElement e) =>
      e.knownType == ElementType.text && e.rotation == 0 ? e.rect.topCenter : e.rect.center;

  Stroke _onSurface(Stroke s, int createdAt) => Stroke(
    id: s.id,
    surfaceId: _model.surfaceId,
    tool: s.tool,
    color: s.color,
    width: s.width,
    points: s.points,
    createdAt: createdAt,
    style: s.style,
    shape: s.shape,
  );

  /// Replaces the selected items with [strokes] (one per selected stroke,
  /// in order; or the very same list to keep them) and [elements] (matched
  /// by id) as one undoable edit, each on the surface it was stored on —
  /// or, with [transfer], on the page under its centre.
  void _replace(
    List<Stroke> strokes,
    List<SurfaceElement> elements, {
    SelectionFrame? frame,
    bool transfer = false,
  }) {
    final plan = SelectionPlan(_model);
    final same = identical(strokes, _strokes);
    for (var i = 0; i < _strokes.length; i++) {
      final source = _sources[_strokes[i].id];
      same ? plan.keepStroke(_strokes[i], source) : plan.removeStroke(_strokes[i], source);
    }
    if (!same) {
      ShiftedSurface? to(int i) => _target(
        strokes[i].bounds.center,
        i < _strokes.length ? _sources[_strokes[i].id] : null,
        transfer: transfer,
      );
      final connected = _connect(strokes, plan, (i) => to(i)?.model ?? _model);
      for (var i = 0; i < connected.length; i++) {
        plan.addStroke(connected[i], to: to(i));
      }
    }
    for (final e in _elements) {
      plan.removeElement(e, _sources[e.id]);
    }
    for (final e in elements) {
      final from = _sources[e.id];
      plan.addElement(
        e,
        to: _target(e.rect.center, from, transfer: transfer),
        from: from,
      );
    }
    _apply(plan, frame: frame);
  }

  /// Where an item centred on [centre] goes: with [transfer] the page under
  /// it, else (or when it is on no page) the surface it came [from].
  ShiftedSurface? _target(Offset centre, SelectionSource? from, {required bool transfer}) {
    final here = transfer ? surfaces?.at(_model, centre) : null;
    return here ?? from?.surface;
  }

  /// Commits [plan] and selects what it leaves selected.
  void _apply(SelectionPlan plan, {SelectionFrame? frame}) {
    _commit(plan);
    select(plan.strokes, plan.elements, frame: frame, sources: plan.sources);
  }

  /// Commits [plan] (one undo step) without the change listener dropping
  /// the selection.
  void _commit(SelectionPlan plan) {
    _editing = true;
    try {
      void commit() =>
          _committedTo = plan.commit(surfaces?.batch ?? (edits) => edits(), mergeInto: _mergeInto);
      final chains = flows;
      if (chains == null || !plan.touchesText) return commit();
      // Text boxes flow across pages: one step with what that changes.
      chains.pages.batch(() {
        plan.flowText(chains);
        commit();
      });
    } finally {
      _editing = false;
    }
  }
}
