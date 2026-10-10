import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../core/clock.dart';
import '../../domain/stroke.dart';
import '../../domain/surface_element.dart';
import '../elements/element_renderer.dart';
import '../geometry/affine.dart';
import '../render/stroke_renderer.dart';
import '../surface_model.dart';
import '../undo_history.dart';
import 'ink_clipboard.dart';
import 'selection_frame.dart';
import 'transform_items.dart';

/// The current lasso selection on a surface and the edits applied to it.
///
/// Selected items are hidden from the committed ink layer and drawn from
/// one cached [picture] instead, so a drag only changes the [preview]
/// transform — nothing is re-tessellated until the gesture ends. Each
/// gesture or action commits one undoable [InkEdit] (strokes are replaced
/// by transformed copies; elements keep their ids).
class SelectionController extends ChangeNotifier {
  SelectionController({required this._model, required this.clipboard, this.clock = const Clock()}) {
    _model.addListener(_onModelChanged);
  }

  final InkClipboard clipboard;
  final Clock clock;

  SurfaceModel _model;
  SurfaceModel get model => _model;
  set model(SurfaceModel value) {
    if (identical(value, _model)) return;
    clear();
    _model.removeListener(_onModelChanged);
    _model = value..addListener(_onModelChanged);
  }

  List<Stroke> _strokes = const [];
  List<SurfaceElement> _elements = const [];
  SelectionFrame? _frame;
  SelectionFrame? _previewFrame;
  Affine _preview = Affine.identity;
  ui.Picture? _picture;
  bool _editing = false;

  List<Stroke> get strokes => _strokes;
  List<SurfaceElement> get elements => _elements;
  bool get isEmpty => _strokes.isEmpty && _elements.isEmpty;

  /// The frame as shown (including an in-progress gesture).
  SelectionFrame? get frame => _previewFrame ?? _frame;

  /// Transform of the in-progress gesture, applied to [picture].
  Affine get preview => _preview;

  /// The selected content as recorded at selection time (world coords).
  ui.Picture? get picture => _picture;

  /// Selects [strokes] and [elements] (replacing any previous selection).
  void select(
    Iterable<Stroke> strokes,
    Iterable<SurfaceElement> elements, {
    SelectionFrame? frame,
  }) {
    _strokes = List.unmodifiable(strokes);
    _elements = List.unmodifiable(elements);
    _preview = Affine.identity;
    _previewFrame = null;
    _picture?.dispose();
    _picture = null;
    if (isEmpty) {
      _frame = null;
      _model.setHidden(const {});
    } else {
      _frame = frame ?? SelectionFrame(boundsOf(_strokes, _elements));
      _picture = _record();
      _model.setHidden({for (final s in _strokes) s.id, for (final e in _elements) e.id});
    }
    notifyListeners();
  }

  void clear() {
    if (isEmpty && _frame == null) return;
    select(const [], const []);
  }

  // ---------------------------------------------------------------------------
  // Transform gestures

  /// Shows [t] (with the resulting [frame]) without committing anything.
  void setPreview(Affine t, SelectionFrame frame) {
    _preview = t;
    _previewFrame = frame;
    notifyListeners();
  }

  /// Commits the previewed transform as one undoable edit.
  void commitPreview() {
    final t = _preview;
    final frame = _previewFrame;
    if (t.isIdentity || frame == null) {
      cancelPreview();
      return;
    }
    final strokes = [for (final s in _strokes) TransformItems.stroke(s, t, id: clock.newId())];
    final elements = [for (final e in _elements) TransformItems.element(e, t)];
    _replace(strokes, elements, frame: frame);
  }

  void cancelPreview() {
    if (_previewFrame == null && _preview.isIdentity) return;
    _preview = Affine.identity;
    _previewFrame = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Actions

  void delete() {
    if (isEmpty) return;
    _edit(() => _model.commit(InkEdit(removed: _strokes, removedElements: _elements)));
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

  /// Recolours every selected stroke and text box.
  void recolor(int argb) {
    if (isEmpty) return;
    _replace(
      [for (final s in _strokes) TransformItems.recolorStroke(s, argb, id: clock.newId())],
      [for (final e in _elements) TransformItems.recolorElement(e, argb)],
      frame: _frame,
    );
  }

  // ---------------------------------------------------------------------------
  // Internals

  void _paste(List<Stroke> strokes, List<SurfaceElement> elements, Rect bounds, Offset at) {
    final t = Affine.translation(at - bounds.center);
    final now = clock.nowMs();
    final ordered = [...strokes]..sort(Stroke.paintOrder);
    final orderedElements = [...elements]..sort(SurfaceElement.paintOrder);
    final top = _model.topZ;
    final newStrokes = [
      for (var i = 0; i < ordered.length; i++)
        _onSurface(TransformItems.stroke(ordered[i], t, id: clock.newId()), now + i),
    ];
    final newElements = [
      for (var i = 0; i < orderedElements.length; i++)
        TransformItems.element(
          orderedElements[i],
          t,
        ).copyWith(id: clock.newId(), surfaceId: _model.surfaceId, z: top + 1 + i, createdAt: now),
    ];
    _edit(() => _model.commit(InkEdit(added: newStrokes, addedElements: newElements)));
    select(newStrokes, newElements);
  }

  Stroke _onSurface(Stroke s, int createdAt) => Stroke(
    id: s.id,
    surfaceId: _model.surfaceId,
    tool: s.tool,
    color: s.color,
    width: s.width,
    points: s.points,
    createdAt: createdAt,
    style: s.style,
  );

  void _replace(List<Stroke> strokes, List<SurfaceElement> elements, {SelectionFrame? frame}) {
    final edit = InkEdit(
      added: strokes,
      removed: _strokes,
      addedElements: elements,
      removedElements: _elements,
    );
    _edit(() => _model.commit(edit));
    select(strokes, elements, frame: frame);
  }

  /// Runs a model edit without the change listener dropping the selection.
  void _edit(void Function() action) {
    _editing = true;
    try {
      action();
    } finally {
      _editing = false;
    }
  }

  /// Drops the selection when its content changes underneath it (undo,
  /// redo, erasing, a sync reload).
  void _onModelChanged() {
    if (_editing || isEmpty) return;
    final stale =
        _strokes.any((s) => !identical(_model.strokeById(s.id), s)) ||
        _elements.any((e) => !identical(_model.elementById(e.id), e));
    if (stale) clear();
  }

  ui.Picture _record() {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final ordered = [..._strokes]..sort(Stroke.paintOrder);
    for (final s in ordered) {
      if (s.tool.isHighlighter) StrokeRenderer.draw(canvas, s);
    }
    for (final s in ordered) {
      if (!s.tool.isHighlighter) StrokeRenderer.draw(canvas, s);
    }
    for (final e in [..._elements]..sort(SurfaceElement.paintOrder)) {
      ElementRenderer.draw(canvas, e);
    }
    return recorder.endRecording();
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

  @override
  void dispose() {
    _model.removeListener(_onModelChanged);
    _picture?.dispose();
    super.dispose();
  }
}
