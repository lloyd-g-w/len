part of 'canvas_minimap.dart';

/// The minimap's own viewport: what it shows, moved at once or gliding, and
/// the gestures that zoom and pan it.
extension _MinimapViewport on _CanvasMinimapState {
  /// Shows [next], gliding there or at once.
  void _moveTo(Rect next, {bool glide = false}) {
    if (next == _to) return;
    if (_to != null && glide) {
      _from = _frame;
      _to = next;
      _glide.forward(from: 0);
      return;
    }
    _stopGlide();
    _to = next;
    _moved.value++;
  }

  void _stopGlide() {
    if (_from == null) return;
    _to = _frame;
    _from = null;
    _glide.value = 1;
  }

  /// A gesture starts on the map: it holds still under the finger.
  void _hold() {
    _stopGlide();
    _holding = true;
  }

  /// The gesture ended; after a drag of the view ([dragged]), a zoomed map
  /// glides after the view if it was left off it.
  void _release({required bool dragged}) {
    _holding = false;
    if (dragged) _tracking = true;
    _onView(glide: dragged);
  }

  /// Zooms the map by [factor] and pans it so the world point under [from]
  /// (map pixels) comes under [to]; zoomed all the way out, it fits again.
  void _transform(Offset from, Offset to, [double factor = 1]) {
    final fit = _fit;
    if (fit == null) return;
    final next = MinimapView.transform(
      _frame,
      size: widget.size,
      fit: fit,
      maxZoom: MinimapView.maxZoom(fit, _content.cellSize),
      from: from,
      to: to,
      factor: factor,
    );
    _setCustom(next.width >= fit.width ? null : next);
    _tracking = MinimapView.tracks(next, _nav.visibleArea);
    _moveTo(next);
  }

  /// Fits the map to everything again (the fit button, its menu).
  void _fitMap() {
    _setCustom(null);
    _tracking = true;
    if (_fit case final fit?) _moveTo(fit, glide: true);
  }

  MinimapProjection _projection() => MinimapProjection(_frame, widget.size);
}
