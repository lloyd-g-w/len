part of 'ink_input_controller.dart';

/// Where a landing stylus or finger goes (see [InkInputController]'s
/// routing rules), and what a hovering pointer shows.
extension _InputRouting on InkInputController {
  void _stylusDown(PointerDownEvent e) {
    _noteStylus();
    if (_draw.pointer != null) {
      if (_draw.byStylus) {
        // There is only one pen: its previous contact lost its up event.
        _draw.finish();
      } else {
        _draw.cancel(); // Probably a palm touched down first.
      }
    }
    // Fingers resting on the screen are the palm now; stop them panning.
    _nav.clear(at: e.localPosition);
    final route = routeStylus(e.kind, e.buttons, penButtonAction);
    final eraserTool = route == StylusRoute.tool && tools.tool == EditorTool.eraser;
    _draw.start(
      e,
      erase: route == StylusRoute.eraser || eraserTool,
      lasso: route == StylusRoute.lasso,
    );
  }

  void _touchDown(PointerDownEvent e) {
    // A palm while writing, or between strokes.
    if (_draw.byStylus ||
        _stylus.isNear(e.timeStamp, within: InkInputController.palmQuiet) ||
        (palms?.stylusNear(e.timeStamp, within: InkInputController.palmQuiet) ?? false)) {
      return;
    }
    // Android reports no hover exit for a stylus leaving range, so a stale
    // cursor would linger; a finger is a good moment to clear it.
    _draw.showEraser(null);
    _draw.showPen(null);
    // Palm rejection, or reading (one finger scrolls until a tool is chosen).
    if (tools.fingersNavigate) {
      _nav.add(e.pointer, e.localPosition, slop: kTouchSlop);
      return;
    }
    final drawing = _draw.pointer;
    if (drawing == null && _nav.isEmpty) {
      _draw.start(e, erase: tools.tool == EditorTool.eraser);
      return;
    }
    if (drawing != null && _draw.kind == PointerDeviceKind.touch) {
      // A second finger: the first one was the start of a pinch, not ink.
      final firstPosition = _draw.lastScreen!;
      _draw.cancel();
      _nav.add(drawing, firstPosition, slop: kTouchSlop);
    }
    _nav.add(e.pointer, e.localPosition, slop: kTouchSlop);
  }

  bool _wantsErase(PointerEvent e) =>
      tools.tool == EditorTool.eraser ||
      routeStylus(e.kind, e.buttons, penButtonAction) == StylusRoute.eraser;

  /// Whether a hovering [e] previews the ink it would make: a stylus's
  /// writing end with the pen or highlighter, its side button not routing
  /// elsewhere.
  bool _previewsInk(PointerEvent e) =>
      e.kind == PointerDeviceKind.stylus &&
      (tools.tool == EditorTool.pen || tools.tool == EditorTool.highlighter) &&
      routeStylus(e.kind, e.buttons, penButtonAction) == StylusRoute.tool;

  void _noteStylus() {
    if (_stylusSeen) return;
    _stylusSeen = true;
    onStylusDetected?.call();
  }
}
