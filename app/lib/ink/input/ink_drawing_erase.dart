part of 'ink_drawing.dart';

/// Erasing along a contact; a finger's erasing held back while it may be
/// a resting palm or the start of a pinch.
extension _InkErasing on InkDrawing {
  /// Starts erasing at [e] (a finger's held back).
  void _beginErase(PointerDownEvent e) {
    showEraser(e.localPosition);
    if (e.kind == PointerDeviceKind.touch) {
      _heldErase = [e.localPosition];
    } else {
      _eraseTo(e.localPosition);
    }
  }

  /// Erases to [screen], or holds it while a finger may not be erasing.
  void _eraseOrHold(Offset screen) {
    final held = _heldErase;
    if (held == null) return _eraseTo(screen);
    held.add(screen);
    _lastScreen = screen;
    if ((screen - _drawStartScreen).distance > kTouchSlop) _releaseErase();
  }

  /// Erases along the held finger path: it is erasing after all.
  void _releaseErase() {
    final held = _heldErase;
    if (held == null) return;
    _heldErase = null;
    _lastScreen = held.first;
    held.forEach(_eraseTo);
  }

  void _eraseTo(Offset screen) {
    final from = viewport.toWorld(_lastScreen ?? screen);
    final to = viewport.toWorld(screen);
    // Hits within one drag merge into a single undo step — but only after
    // the first hit, so we never merge into an unrelated earlier edit.
    final erased = model.eraseAlong(
      from,
      to,
      tools.eraserRadius / viewport.scale,
      continueEdit: _eraseStarted,
      mode: tools.eraser.mode,
      highlighterOnly: tools.eraser.highlighterOnly,
    );
    _eraseStarted = _eraseStarted || erased;
    _lastScreen = screen;
  }
}
