part of 'canvas_minimap.dart';

/// The minimap's own viewport: what it shows, moved at once or gliding, the
/// gestures that zoom and pan it, and when its miniature is drawn again.
extension _MinimapViewport on _CanvasMinimapState {
  double get _aspect => widget.size.width / widget.size.height;

  /// The world area shown now (between frames while it glides).
  Rect get _frame {
    final to = _to ?? _nav.visibleArea;
    final from = _from;
    if (from == null || _glide.value >= 1) return to;
    return Rect.lerp(from, to, Motion.standard.transform(_glide.value))!;
  }

  /// Keeps the map in step with the view and the content: refits when the
  /// view leaves the fit; a zoomed map stays put, nudged along while it
  /// follows the view, and fits again only once everything fits in it.
  void _onView({bool glide = false}) {
    if (_holding || _nav.viewport.size.isEmpty) return;
    final view = _nav.visibleArea;
    final fit = MinimapFrame.next(
      previous: _fit,
      content: _sketch.bounds,
      view: view,
      aspect: _aspect,
    );
    if (fit != _fit) {
      _fit = fit;
      _scheduleRaster();
    }
    final custom = _custom;
    if (custom == null || custom.width >= fit.width) {
      _setCustom(null);
      return _moveTo(fit, glide: true);
    }
    var next = MinimapView.clampInto(custom, fit);
    if (_tracking) {
      next = MinimapView.follow(next, fit, view);
    } else {
      _tracking = MinimapView.tracks(next, view);
    }
    _custom = next;
    _moveTo(next, glide: glide);
  }

  /// Sets the map's own viewport, rebuilding when the fit button comes or
  /// goes (after the frame, when the view changed during a layout).
  void _setCustom(Rect? custom) {
    final changed = (custom == null) != (_custom == null);
    _custom = custom;
    if (!changed) return;
    _scheduleRaster();
    if (SchedulerBinding.instance.schedulerPhase != SchedulerPhase.persistentCallbacks) {
      return _rebuild();
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) _rebuild();
    });
  }

  /// Shows [next], gliding there or at once.
  void _moveTo(Rect next, {bool glide = false}) {
    if (next == _to) return;
    // A zoomed map shows its own detail image, drawn again where it went.
    if (_custom != null) _scheduleRaster();
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
    _scheduleRaster();
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
      maxZoom: MinimapView.maxZoom(fit, _sketch.blocks.cellSize),
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

  void _onGlide(AnimationStatus status) {
    if (status == AnimationStatus.completed) _scheduleRaster();
  }

  /// Draws the miniature again shortly (at most every
  /// [CanvasMinimap.rasterDelay]), once the map holds still.
  void _scheduleRaster() {
    if (_rasterTimer?.isActive ?? false) return;
    _rasterTimer = Timer(CanvasMinimap.rasterDelay, () => unawaited(_rasterise()));
  }

  /// The whole map ([_fit]) as an image and, while the map is zoomed or
  /// panned, a sharper one of what it shows.
  Future<void> _rasterise() async {
    if (!mounted) return;
    // Moving: the last images stand in (scaled) until it settles.
    if (_holding || _glide.isAnimating) return;
    if (_rendering) return _scheduleRaster();
    final fit = _fit;
    final sketch = _sketch;
    if (fit == null || sketch.overBudget || sketch.isEmpty) return;
    _rendering = true;
    try {
      _raster.sync(sketch);
      await _raster.render(sketch, fit, widget.size * _dpr, zoomed: _custom);
    } finally {
      _rendering = false;
    }
    if (mounted) _painted.value++;
  }
}
