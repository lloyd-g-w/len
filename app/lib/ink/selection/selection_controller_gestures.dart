part of 'selection_controller.dart';

/// A [SelectionController]'s transform and reshape gestures: shown as a
/// preview while they run, committed (one undoable edit) or dropped at
/// their end.
mixin _SelectionGestures on _SelectionCore {
  /// Shows [t] (with the resulting [frame]) without committing anything.
  void setPreview(Affine t, SelectionFrame frame) {
    _preview = t;
    _previewFrame = frame;
    _previewFollowers(_moved(t));
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
    _replace(strokes, elements, frame: frame, transfer: true);
  }

  void cancelPreview() {
    if (_previewFrame == null && _preview.isIdentity) return;
    _preview = Affine.identity;
    _previewFrame = null;
    _previewFollowers(const {});
    notifyListeners();
  }

  /// Shows [shapeStroke] reshaped to [shape] (a handle being dragged)
  /// without committing anything.
  void reshape(ShapeGeometry shape) {
    final stroke = shapeStroke;
    if (stroke == null) return;
    final reshaped = _reshaped = ShapeBuilder.reshaped(stroke, shape, id: stroke.id);
    _picture?.dispose();
    _picture = _recordSketch([reshaped]);
    _previewFrame = _frameAround([reshaped], const []);
    _previewFollowers(ShapeAnchors.isTarget(shape) ? {stroke.shapeId: reshaped} : const {});
    notifyListeners();
  }

  /// Commits the shape [reshape] showed as one undoable edit (its fill and
  /// look kept), and keeps it selected.
  void commitReshape() {
    final reshaped = _reshaped;
    if (reshaped == null) return;
    final frame = _previewFrame;
    _reshaped = null;
    if (reshaped.shape == _strokes.single.shape) return cancelReshape();
    _replace(
      [reshaped.withPoints(reshaped.points, id: clock.newId(), shape: reshaped.shape)],
      const [],
      frame: frame,
    );
  }

  /// Drops the shape [reshape] showed.
  void cancelReshape() {
    final wasReshaped = _reshaped != null || _previewFrame != null;
    _reshaped = null;
    if (!wasReshaped || isEmpty) return;
    _picture?.dispose();
    _picture = _record(_strokes);
    _previewFrame = null;
    _previewFollowers(const {});
    notifyListeners();
  }
}
