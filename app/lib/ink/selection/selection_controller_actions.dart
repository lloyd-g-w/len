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
  /// (and above the ink).
  void bringToFront() => _restack(ElementOrder.toFront(_elements, _model.topZ));

  /// Moves the selected elements beneath everything else (and the ink).
  void sendToBack() => _restack(ElementOrder.toBack(_elements, _model.bottomZ));

  void _restack(List<SurfaceElement> elements) {
    if (_elements.isEmpty) return;
    _replace(_strokes, elements, frame: _frame);
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
  void restyleInk({
    double? width,
    InkTool? tool,
    StrokeStyle Function(InkTool tool, double width)? styleFor,
  }) {
    if (_strokes.isEmpty) return;
    _replace(
      [
        for (final s in _strokes)
          TransformItems.restyleStroke(
            s,
            width: width,
            tool: tool,
            style: tool == null || tool == s.tool ? null : styleFor?.call(tool, width ?? s.width),
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
