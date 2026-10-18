part of 'zoom_window.dart';

/// Where the frame is and how it moves: placed when the window opens,
/// advanced along the line and wrapped ([ZoomRules]), gliding there
/// (moved by hand: [_ZoomHandMoves]).
mixin _ZoomMoves {
  ZoomHost get host;
  ZoomBoxViewport get view;
  SurfaceModel? get model;

  /// Shows the frame in [view] and loads its ink.
  void _sync();

  /// Moves the window to another surface (the next page).
  void _switchTo(String id);
  void notify();

  /// Whether lines written now run right to left (the setting).
  bool _wantsRightToLeft();

  ZoomFrame? _frame;
  Size _box = Size.zero;

  /// Whether the frame was placed (it waits for the box's size).
  bool _placed = false;

  /// Whether the frame, once the box is laid out, stays where it was put
  /// (kept from before) rather than being placed afresh.
  bool _resume = false;

  /// Where lines begin and end (surface x; see [ZoomRules.lineStart]).
  double _lineStart = 0, _lineEnd = 0;

  /// Whether the current line runs right to left: taken from the setting
  /// when a line starts, so a line keeps its direction.
  bool _rtl = false;

  /// Whether the current line runs right to left.
  bool get rightToLeft => _rtl;

  /// The ink written on the current line (how tall a line is).
  Rect? _lineInk;

  /// An advance waiting for the pen to rest.
  Timer? _pending;

  /// Whether an advance waits for the pen to rest (the box's zone fills
  /// meanwhile, so the move doesn't come as a surprise).
  final ValueNotifier<bool> armed = ValueNotifier(false);

  /// Moves the frame on from ink lifted at [inkEnd] once the pen rested
  /// for [after].
  void _arm(double inkEnd, Duration after) {
    _pending?.cancel();
    armed.value = true;
    _pending = Timer(after, () {
      armed.value = false;
      _advance(inkEnd);
    });
  }

  /// Drops a waiting advance.
  void _disarm() {
    _pending?.cancel();
    armed.value = false;
  }

  Ticker? _glide;
  Offset _glideFrom = Offset.zero, _glideEnd = Offset.zero;

  /// Whether the frame jumps instead of gliding (reduced motion).
  bool reducedMotion = false;

  /// Whether tickers run where the box is (`TickerMode`): a parked split
  /// pane runs none, so a glide waits there (and lands once it shows).
  bool get ticking => _ticking;
  bool _ticking = true;
  set ticking(bool on) {
    _ticking = on;
    _glide?.muted = !on;
  }

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
    rightToLeft: _rtl,
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

  /// Places the frame once the box is laid out: where it was kept, or
  /// afresh.
  void _layOut() {
    if (!_resume) return _place();
    _resume = false;
    final frame = _frame!;
    final sized = frame.copyWith(scale: _rules.scaleForWidth(_box.width / frame.scale));
    _set(sized.copyWith(origin: _rules.clamp(sized, sized.origin)));
    _placed = true;
    _startLine();
    _reveal();
  }

  /// Frames where writing goes on in view: below the ink that shows (its
  /// lines start where that ink does), else a little below the top of
  /// what shows, at the page's margin rule (or near its left edge; on a
  /// canvas, the view's). Right to left, mirrored: at the ink's right, or
  /// as far in from the page's right edge as the margin rule is from its
  /// left.
  void _place() {
    final frame = _frame!;
    final id = frame.surfaceId;
    final page = host.boundsOf(id);
    _rtl = _wantsRightToLeft();
    _lineStart = 0;
    _lineEnd = _rtl ? double.negativeInfinity : double.infinity;
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
    final x = _rtl
        ? (ink == null ? null : math.min(ink.right, area.right)) ??
              (margin != null && page != null
                  ? page.right - (margin - page.left) - (pitch ?? 0) / 2
                  : null) ??
              (page != null ? page.right - page.width * 0.06 : area.right - area.width * 0.08)
        : (ink == null ? null : math.max(ink.left, area.left)) ??
              (margin != null ? margin + (pitch ?? 0) / 2 : null) ??
              (page != null ? page.left + page.width * 0.06 : area.left + area.width * 0.08);
    var y = area.top + area.height * 0.1;
    // Below the ink, if the frame fits there on the page.
    if (ink != null) {
      final below = ink.bottom + (pitch ?? size.height / 3) / 4;
      if (page == null || below + size.height <= page.bottom) y = below;
    }
    _lineStart = x;
    _lineEnd = _rtl
        ? page?.left ?? math.min(area.left + area.width * 0.04, x - 2 * size.width)
        : page?.right ?? math.max(area.right - area.width * 0.04, x + 2 * size.width);
    _lineInk = null;
    _placed = true;
    f = f.copyWith(origin: _rules.clamp(f, Offset(_rtl ? x - size.width : x, y)));
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

  /// A new line starts where the frame is now (in the direction set now).
  void _startLine() {
    final frame = _frame!;
    final rect = frame.rectFor(_box);
    _rtl = _wantsRightToLeft();
    final page = host.boundsOf(frame.surfaceId);
    final free = host.freeArea(frame.surfaceId);
    if (_rtl) {
      _lineStart = rect.right;
      _lineEnd = page?.left ?? math.min(free?.left ?? rect.left, rect.right - 2 * rect.width);
    } else {
      _lineStart = rect.left;
      _lineEnd = page?.right ?? math.max(free?.right ?? rect.right, rect.left + 2 * rect.width);
    }
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

  void _advance(double inkEnd) {
    final frame = _frame;
    if (frame == null || _box.isEmpty) return;
    _apply(_rules.advance(frame, inkEnd, lineStep: _lineStep()));
  }

  /// Goes to the start of the next line (the box's ↵).
  void newLine() {
    final frame = _frame;
    if (frame == null || _box.isEmpty) return;
    _disarm();
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
    _glide =
        Ticker((elapsed) {
            final t = math.min(1.0, elapsed.inMicroseconds / Motion.medium.inMicroseconds);
            final at = Offset.lerp(_glideFrom, _glideEnd, Motion.standard.transform(t))!;
            _set(_frame!.copyWith(origin: at));
            if (t >= 1) _stopGlide();
          }, debugLabel: 'ZoomWindow')
          ..muted = !_ticking
          ..start();
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
}
