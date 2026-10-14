part of 'zoom_window.dart';

/// Where the frame is and how it moves: placed when the window opens,
/// advanced along the line and wrapped ([ZoomRules]), gliding there;
/// dragged and sized on the page, panned and pinched in the box.
mixin _ZoomMoves {
  ZoomHost get host;
  ZoomBoxViewport get view;
  SurfaceModel? get model;

  /// Shows the frame in [view] and loads its ink.
  void _sync();

  /// Moves the window to another surface (the next page).
  void _switchTo(String id);
  void notify();

  ZoomFrame? _frame;
  Size _box = Size.zero;

  /// Whether the frame was placed (it waits for the box's size).
  bool _placed = false;

  /// Where lines begin and end (surface x).
  double _lineStart = 0, _lineEnd = 0;

  /// The ink written on the current line (how tall a line is).
  Rect? _lineInk;

  /// An advance waiting for the pen to rest.
  Timer? _pending;

  Ticker? _glide;
  Offset _glideFrom = Offset.zero, _glideEnd = Offset.zero;

  /// Whether the frame jumps instead of gliding (reduced motion).
  bool reducedMotion = false;

  /// The frame while open.
  ZoomFrame? get frame => _frame;

  /// The box's size (pixels).
  Size get box => _box;

  /// The frame on its surface, once the box is laid out.
  Rect? get frameRect => _box.isEmpty ? null : _frame?.rectFor(_box);

  /// Where the advance zone begins on the surface.
  double? get zoneStart => _frame == null || _box.isEmpty ? null : _rules.zoneStart(_frame!);

  ZoomRules get _rules => ZoomRules(
    box: _box,
    lineStart: _lineStart,
    lineEnd: _lineEnd,
    page: _frame == null ? null : host.boundsOf(_frame!.surfaceId),
  );

  void _set(ZoomFrame frame) {
    _frame = frame;
    _sync();
    notify();
  }

  void _reveal() {
    final rect = frameRect;
    if (rect != null) host.reveal(_frame!.surfaceId, rect);
  }

  /// Frames where writing goes on in view: below the ink that shows (its
  /// lines start where that ink does), else a little below the top of
  /// what shows, at the page's margin rule (or near its left edge; on a
  /// canvas, the view's).
  void _place() {
    final frame = _frame!;
    final id = frame.surfaceId;
    final page = host.boundsOf(id);
    _lineStart = 0;
    _lineEnd = double.infinity;
    final pitch = host.pitchOf(id);
    var f = frame.copyWith(
      scale: _rules.startScale(pitch: pitch, viewWidth: host.viewWidth),
    );
    final size = _box / f.scale;
    final free = host.freeArea(id);
    var area = free ?? page ?? Offset.zero & size;
    if (page != null) area = free != null && free.overlaps(page) ? free.intersect(page) : page;
    final ink = _inkIn(area);
    final margin = host.marginOf(id);
    final x =
        (ink == null ? null : math.max(ink.left, area.left)) ??
        (margin != null ? margin + (pitch ?? 0) / 2 : null) ??
        (page != null ? page.left + page.width * 0.06 : area.left + area.width * 0.08);
    var y = area.top + area.height * 0.1;
    // Below the ink, if the frame fits there on the page.
    if (ink != null) {
      final below = ink.bottom + (pitch ?? size.height / 3) / 4;
      if (page == null || below + size.height <= page.bottom) y = below;
    }
    _lineStart = x;
    _lineEnd = page?.right ?? math.max(area.right - area.width * 0.04, x + 2 * size.width);
    _lineInk = null;
    _placed = true;
    f = f.copyWith(origin: _rules.clamp(f, Offset(x, y)));
    _set(f);
    _reveal();
  }

  /// The bounds of the ink and text loaded in [area], or null.
  Rect? _inkIn(Rect area) {
    final model = this.model;
    if (model == null) return null;
    Rect? ink;
    void add(Rect r) {
      if (r.overlaps(area)) ink = ink?.expandToInclude(r) ?? r;
    }

    for (final stroke in model.strokesNear(area)) {
      add(stroke.bounds);
    }
    for (final element in model.elementsNear(area)) {
      add(element.bounds);
    }
    return ink;
  }

  /// A new line starts where the frame is now.
  void _startLine() {
    final frame = _frame!;
    final rect = frame.rectFor(_box);
    _lineStart = rect.left;
    final page = host.boundsOf(frame.surfaceId);
    final free = host.freeArea(frame.surfaceId);
    _lineEnd = page?.right ?? math.max(free?.right ?? rect.right, rect.left + 2 * rect.width);
    _lineInk = null;
  }

  // ---------------------------------------------------------------------------
  // Advancing

  double _lineStep() {
    final frame = _frame!;
    return ZoomRules.lineStep(
      frameHeight: _box.height / frame.scale,
      inkHeight: _lineInk?.height ?? 0,
      pitch: host.pitchOf(frame.surfaceId),
    );
  }

  void _advance(double inkRight) {
    final frame = _frame;
    if (frame == null || _box.isEmpty) return;
    _apply(_rules.advance(frame, inkRight, lineStep: _lineStep()));
  }

  /// Goes to the start of the next line (the box's ↵).
  void newLine() {
    final frame = _frame;
    if (frame == null || _box.isEmpty) return;
    _pending?.cancel();
    _finishGlide();
    _apply(_rules.newLine(frame, lineStep: _lineStep()));
  }

  void _apply(ZoomMove move) {
    final frame = _frame!;
    switch (move) {
      case ZoomMoveTo(:final origin):
        if (origin.dy != frame.origin.dy) _lineInk = null;
        _glideTo(origin);
      case ZoomNextPage(:final origin):
        final next = host.nextPage(frame.surfaceId);
        if (next == null) return;
        _switchTo(next);
        _frame = frame.copyWith(surfaceId: next);
        _lineInk = null;
        _set(_frame!.copyWith(origin: _rules.clamp(_frame!, origin)));
        // Turns to it (one page at a time) or makes it the active page.
        host.activate(next);
        _reveal();
    }
  }

  void _glideTo(Offset to) {
    final frame = _frame!;
    _stopGlide();
    if (to == frame.origin) return;
    host.reveal(frame.surfaceId, frame.copyWith(origin: to).rectFor(_box));
    if (reducedMotion) return _set(frame.copyWith(origin: to));
    _glideFrom = frame.origin;
    _glideEnd = to;
    _glide = Ticker((elapsed) {
      final t = math.min(1.0, elapsed.inMicroseconds / Motion.medium.inMicroseconds);
      final at = Offset.lerp(_glideFrom, _glideEnd, Motion.standard.transform(t))!;
      _set(_frame!.copyWith(origin: at));
      if (t >= 1) _stopGlide();
    }, debugLabel: 'ZoomWindow')..start();
  }

  /// Jumps a glide in progress to its end (the pen came back).
  void _finishGlide() {
    if (_glide == null) return;
    _stopGlide();
    _set(_frame!.copyWith(origin: _glideEnd));
  }

  void _stopGlide() {
    _glide?.dispose();
    _glide = null;
  }

  // ---------------------------------------------------------------------------
  // Moving and sizing by hand

  /// Where a drag of the frame on the page view has taken it (main-view
  /// world coordinates, unclamped).
  Offset? _dragAt;

  /// Drags the frame on the page view by [screenDelta]; it moves onto the
  /// page its middle is over. Lines start where it is let go.
  void dragBy(Offset screenDelta) {
    final frame = _frame;
    if (frame == null || _box.isEmpty) return;
    _pending?.cancel();
    _finishGlide();
    final origin = host.originOf(frame.surfaceId);
    if (origin == null) return;
    final at = _dragAt = (_dragAt ?? origin + frame.origin) + screenDelta / host.main.scale;
    final size = _box / frame.scale;
    final id = host.surfaceAt(at + size.center(Offset.zero)) ?? frame.surfaceId;
    if (id != frame.surfaceId) {
      _switchTo(id);
      _frame = frame.copyWith(surfaceId: id);
    }
    final local = at - (host.originOf(id) ?? Offset.zero);
    _set(_frame!.copyWith(origin: _rules.clamp(_frame!, local)));
    _startLine();
  }

  /// The drag of the frame ended.
  void dragEnd() {
    _dragAt = null;
    if (_frame != null) _reveal();
  }

  /// Sizes the frame [width] surface units wide (its handle on the page),
  /// keeping its top-left corner.
  void resizeTo(double width) {
    final frame = _frame;
    if (frame == null || _box.isEmpty) return;
    final scale = _rules.scaleForWidth(math.max(width, ZoomRules.minCanvasWidth));
    final sized = frame.copyWith(scale: scale);
    _set(sized.copyWith(origin: _rules.clamp(sized, frame.origin)));
    final rect = frameRect!;
    if (_lineEnd < rect.right) _lineEnd = rect.right;
  }

  /// Fingers panned the box: the frame moves the other way.
  void _panBox(Offset screenDelta) {
    final frame = _frame;
    if (frame == null) return;
    _pending?.cancel();
    _finishGlide();
    final origin = _rules.clamp(frame, frame.origin - screenDelta / frame.scale);
    _set(frame.copyWith(origin: origin));
    if (origin.dx < _lineStart) _lineStart = origin.dx;
    _reveal();
  }

  /// Fingers pinched the box: the frame shrinks (magnifying) or grows
  /// about the point under them.
  void _zoomBox(Offset focal, double scale) {
    final frame = _frame;
    if (frame == null || _box.isEmpty) return;
    final rules = _rules;
    final clamped = rules.scaleForWidth(math.max(_box.width / scale, ZoomRules.minCanvasWidth));
    final world = view.toWorld(focal);
    final sized = frame.copyWith(scale: clamped);
    _set(sized.copyWith(origin: rules.clamp(sized, world - focal / clamped)));
    _reveal();
  }
}
