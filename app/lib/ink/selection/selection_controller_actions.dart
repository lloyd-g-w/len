part of 'selection_controller.dart';

/// The current lasso selection on a surface and the edits applied to it.
///
/// Selected items are hidden from the committed ink layer and drawn from
/// one cached [picture] instead, so a drag only changes the [preview]
/// transform — nothing is re-tessellated until the gesture ends. Each
/// gesture or action commits one undoable [InkEdit] (strokes are replaced
/// by transformed copies; elements keep their ids).
///
/// With [surfaces] (the pages of a paged notebook) a selection can hold
/// items of other pages too, as copies moved into this surface's
/// coordinates: a lasso drawn across pages selects on each, and items moved
/// so their centre lands on another page move to that page (one undo step).
class SelectionController extends _SelectionCore {
  SelectionController({
    required super.model,
    required super.clipboard,
    super.clock = const Clock(),
  });

  void delete() {
    if (isEmpty) return;
    final plan = SelectionPlan(_model);
    for (final s in _strokes) {
      plan.removeStroke(s, _sources[s.id]);
    }
    for (final e in _elements) {
      plan.removeElement(e, _sources[e.id]);
    }
    _commit(plan);
    clear();
  }

  /// Moves the selection by [delta] (world units, e.g. points on a page):
  /// arrow-key nudges. A burst of nudges is one undo step: a nudge within
  /// [nudgeBurst] of the previous one joins its step, unless anything else
  /// was edited or undone in between (or the move spans pages). Ignored
  /// while a gesture changes the selection (it commits what it shows).
  void nudge(Offset delta) {
    final frame = this.frame;
    if (isEmpty || frame == null || delta == Offset.zero || isChanging) return;
    final now = clock.nowMs();
    final last = _lastNudge;
    final history = last?.model.history;
    final joins =
        last != null &&
        now - last.at <= nudgeBurst.inMilliseconds &&
        history!.recorded == last.recorded &&
        !history.canRedo;
    final moved = frame.moved(delta);
    setPreview(moved.transform, moved.frame);
    _mergeInto = joins ? last.model : null;
    _committedTo = null;
    try {
      commitPreview();
    } finally {
      _mergeInto = null;
    }
    final model = _committedTo;
    _lastNudge = model == null ? null : (model: model, recorded: model.history.recorded, at: now);
  }

  /// How long after a nudge the next one still joins its undo step.
  static const nudgeBurst = Duration(seconds: 1);

  /// The surface the last nudge committed to, its undo count then and when.
  ({SurfaceModel model, int recorded, int at})? _lastNudge;

  void copy() {
    if (isEmpty) return;
    clipboard.put(_strokes, _elements, boundsOf(_strokes, _elements));
  }

  void cut() {
    copy();
    delete();
  }

  /// Adds a copy of the selection slightly offset and selects it.
  void duplicate() {
    if (isEmpty) return;
    final bounds = boundsOf(_strokes, _elements);
    _paste(_strokes, _elements, bounds, bounds.center + const Offset(24, 24));
  }

  /// Pastes the clipboard centred on world point [at] and selects it.
  void paste(Offset at) {
    if (clipboard.isEmpty) return;
    _paste(clipboard.strokes, clipboard.elements, clipboard.bounds, at);
  }

  /// Adds a copy of [strokes] and [elements] (from any surface; [bounds]
  /// around them) centred on world point [at] and selects it, e.g. a
  /// selection dropped here from another editor.
  void pasteItems(List<Stroke> strokes, List<SurfaceElement> elements, Rect bounds, Offset at) {
    if (strokes.isEmpty && elements.isEmpty) return;
    _paste(strokes, elements, bounds, at);
  }

  /// Moves the selected elements above everything else on the surface
  /// (and above the ink), and the selected strokes above the ink they
  /// overlap; one undoable edit.
  void bringToFront() => _arrange(front: true);

  /// Moves the selected elements beneath everything else (and the ink),
  /// and the selected strokes beneath the ink they overlap.
  void sendToBack() => _arrange(front: false);

  void _arrange({required bool front}) {
    if (isEmpty) return;
    final elements = _elements.isEmpty
        ? _elements
        : front
        ? ElementOrder.toFront(_elements, _model.topZ)
        : ElementOrder.toBack(_elements, _model.bottomZ);
    final times = _strokes.isEmpty
        ? null
        : StrokeOrder.restacked(_strokes, _overlappedInkTimes(), front: front);
    if (times == null && _elements.isEmpty) return;
    final strokes = times == null
        ? _strokes
        : [
            for (final s in _strokes)
              Stroke(
                id: clock.newId(),
                surfaceId: s.surfaceId,
                tool: s.tool,
                color: s.color,
                width: s.width,
                points: s.points,
                createdAt: times[s.id]!,
                style: s.style,
                shape: s.shape,
              ),
          ];
    _replace(strokes, elements, frame: _frame);
  }

  /// When the unselected ink overlapping the selected strokes was drawn.
  List<int> _overlappedInkTimes() {
    final ids = {for (final s in _strokes) s.id};
    final boxes = [for (final s in _strokes) s.bounds];
    final area = boxes.reduce((a, b) => a.expandToInclude(b));
    return [
      for (final s in _model.strokesNear(area))
        if (!ids.contains(s.id) && boxes.any(s.bounds.overlaps)) s.createdAt,
    ];
  }

  /// Recolours every selected stroke and text box.
  void recolor(int argb) {
    if (isEmpty) return;
    _replace(
      [for (final s in _strokes) TransformItems.recolorStroke(s, argb, id: clock.newId())],
      [for (final e in _elements) TransformItems.recolorElement(e, argb)],
      frame: _frame,
    );
  }

  /// Gives every selected closed shape ([Stroke.isClosed]) the fill
  /// [fillFor] makes from its ink colour (null: none), as one undoable
  /// edit; other strokes and elements are kept.
  void refill(int? Function(Stroke stroke) fillFor) {
    if (!_strokes.any((s) => s.isClosed && s.style.fill != fillFor(s))) return;
    _replace(
      [
        for (final s in _strokes)
          TransformItems.refillStroke(s, s.isClosed ? fillFor(s) : null, id: clock.newId()),
      ],
      _elements,
      frame: _frame,
    );
  }

  /// Changes every selected text box by [update] (font, size, …) as one
  /// undoable edit; strokes and other elements are kept.
  void restyleText(TextData Function(TextData) update) {
    if (!_elements.any((e) => e.knownType == ElementType.text)) return;
    _replace(_strokes, [
      for (final e in _elements) TransformItems.restyleText(e, update),
    ], frame: null);
  }

  /// Gives every selected stroke line [width] and/or pen [tool] (with the
  /// [StrokeStyle] [styleFor] makes for it) as one undoable edit.
  void restyleInk({double? width, InkTool? tool, StrokeStyle Function(InkTool tool)? styleFor}) {
    if (_strokes.isEmpty) return;
    _replace(
      [
        for (final s in _strokes)
          TransformItems.restyleStroke(
            s,
            width: width,
            tool: tool,
            style: tool == null || tool == s.tool ? null : styleFor?.call(tool),
            id: clock.newId(),
          ),
      ],
      _elements,
      frame: width == null ? _frame : null,
    );
  }

  /// Replaces the selected strokes with [added] elements ("Convert to
  /// text") as one undoable edit and selects them (with any selected
  /// elements).
  void replaceStrokesWith(List<SurfaceElement> added) {
    if (_strokes.isEmpty) return;
    final plan = SelectionPlan(_model);
    for (final s in _strokes) {
      plan.removeStroke(s, _sources[s.id]);
    }
    for (final e in _elements) {
      plan.keepElement(e, _sources[e.id]);
    }
    for (final e in added) {
      plan.addElement(e, to: _target(e.rect.center, null, transfer: true));
    }
    _apply(plan);
  }

  /// Makes [elements] the selected elements, replacing the selected ones on
  /// the surface (e.g. adding a link over the selected content, or
  /// removing one) as one undoable edit; the strokes stay.
  void replaceElements(List<SurfaceElement> elements) {
    if (isEmpty) return;
    _replace(_strokes, elements);
  }

  /// Places a copy of [strokes] and [elements] (laid out within [bounds])
  /// centred on world point [at], like a paste, and selects it.
  void place(List<Stroke> strokes, List<SurfaceElement> elements, Rect bounds, Offset at) {
    if (strokes.isEmpty && elements.isEmpty) return;
    _paste(strokes, elements, bounds, at);
  }

  /// Tight world bounds of strokes (their points plus half the line width)
  /// and elements.
  static Rect boundsOf(List<Stroke> strokes, List<SurfaceElement> elements) {
    Rect? r;
    for (final s in strokes) {
      final b = Stroke.computeBounds(s.points, s.width / 2);
      r = r == null ? b : r.expandToInclude(b);
    }
    for (final e in elements) {
      r = r == null ? e.bounds : r.expandToInclude(e.bounds);
    }
    return r ?? Rect.zero;
  }
}
