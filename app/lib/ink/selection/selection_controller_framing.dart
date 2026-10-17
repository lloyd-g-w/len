part of 'selection_controller.dart';

/// Drawing and framing the selected items: the lifted picture, the frame
/// around a new selection, and whether an item is still what is stored.
extension _SelectionFraming on _SelectionCore {
  /// Whether selected item [item] is still what its surface stores.
  bool _stored(String id, Object item, Object? Function(SurfaceModel) lookup) {
    final source = _sources[id];
    return identical(lookup(source?.surface.model ?? _model), source?.original ?? item);
  }

  ui.Picture _record(List<Stroke> strokes, [List<SurfaceElement>? elements]) {
    final recorder = ui.PictureRecorder();
    ContentPainter.paint(
      Canvas(recorder),
      strokes,
      elements ?? _elements,
      images: _model.images,
      pixelScale: pixelScale,
    );
    return recorder.endRecording();
  }

  /// [strokes] (shapes, recorded anew on every move of a gesture: a handle
  /// dragged, lines following a shape) drawn as even lines along their
  /// points ([StrokeRenderer.drawSketch]): a shape's outline is an even
  /// line with round ends, so this is how it looks, without building
  /// outlines (nearly all of a move's time). The commit builds them once.
  ui.Picture _recordSketch(List<Stroke> strokes) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (final s in [...strokes]..sort(Stroke.drawOrder)) {
      StrokeRenderer.drawSketch(canvas, s);
    }
    return recorder.endRecording();
  }

  /// A new selection's frame: around a single element it follows the
  /// element's rotation (so handles sit on its edges), otherwise it is the
  /// axis-aligned bounds.
  SelectionFrame _frameAround(List<Stroke> strokes, List<SurfaceElement> elements) {
    if (strokes.isEmpty && elements.length == 1) {
      final e = elements.single;
      return SelectionFrame(e.rect.inflate(framePadding), e.rotation);
    }
    // A single shape: turned with it, so its handles sit on the frame.
    if (strokes.length == 1 && elements.isEmpty && strokes.single.shape != null) {
      final s = strokes.single;
      final angle = ShapeHandles.angleOf(s.shape!);
      return SelectionFrame.around(
        [for (final p in s.points) p.offset],
        angle,
        framePadding + s.width / 2,
      );
    }
    return SelectionFrame(SelectionController.boundsOf(strokes, elements).inflate(framePadding));
  }
}
