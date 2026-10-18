part of 'zoom_window.dart';

/// The frame moved by hand: dragged and sized on the page, panned and
/// pinched in the box.
mixin _ZoomHandMoves on _ZoomMoves {
  /// Where a drag of the frame on the page view has taken it (main-view
  /// world coordinates, unclamped).
  Offset? _dragAt;

  /// Drags the frame on the page view by [screenDelta]; it moves onto the
  /// page its middle is over. Lines start where it is let go.
  void dragBy(Offset screenDelta) {
    final frame = _frame;
    if (frame == null || _box.isEmpty) return;
    _disarm();
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
  /// keeping its top corner at the line's start: the top-left, or (right
  /// to left) the top-right.
  void resizeTo(double width) {
    final frame = _frame;
    if (frame == null || _box.isEmpty) return;
    final scale = _rules.scaleForWidth(math.max(width, ZoomRules.minCanvasWidth));
    final sized = frame.copyWith(scale: scale);
    final right = frame.origin.dx + _box.width / frame.scale;
    final origin = _rtl ? Offset(right - _box.width / scale, frame.origin.dy) : frame.origin;
    _set(sized.copyWith(origin: _rules.clamp(sized, origin)));
    final rect = frameRect!;
    if (_rtl) {
      if (_lineEnd > rect.left) _lineEnd = rect.left;
    } else if (_lineEnd < rect.right) {
      _lineEnd = rect.right;
    }
  }

  /// Fingers panned the box: the frame moves the other way.
  void _panBox(Offset screenDelta) {
    final frame = _frame;
    if (frame == null) return;
    _disarm();
    _finishGlide();
    final origin = _rules.clamp(frame, frame.origin - screenDelta / frame.scale);
    _set(frame.copyWith(origin: origin));
    if (_rtl) {
      final right = origin.dx + _box.width / frame.scale;
      if (right > _lineStart) _lineStart = right;
    } else if (origin.dx < _lineStart) {
      _lineStart = origin.dx;
    }
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
