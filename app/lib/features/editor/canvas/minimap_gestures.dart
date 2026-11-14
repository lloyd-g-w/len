part of 'canvas_minimap.dart';

/// What a press on the map took hold of.
enum _Grip { map, frame, corner }

/// The minimap's input. One pointer (touch, pen or mouse) moves the
/// canvas's view: a tap glides it there, a second tap soon after zooms in
/// there; a drag moves it live (grabbing the frame keeps the point under
/// the finger, elsewhere centres the view under it); dragging a corner of
/// the frame resizes it, zooming the canvas (the opposite corner stays).
/// The map itself is moved by everything else, never the canvas: two
/// fingers (or a trackpad) pinch to zoom it about their middle and drag to
/// pan it; the wheel pans it (Shift: across), Ctrl+wheel zooms it about the
/// pointer. Long-press or right-click opens the menu.
class _MinimapGestures extends StatefulWidget {
  const _MinimapGestures({required this.state, required this.child});

  final _CanvasMinimapState state;
  final Widget child;

  @override
  State<_MinimapGestures> createState() => _MinimapGesturesState();
}

class _MinimapGesturesState extends State<_MinimapGestures> {
  final MenuController _menu = MenuController();

  /// Where the latest pointer went down (a drag is reported past the slop).
  Offset? _down;

  /// From the view's centre to the world point grabbed.
  Offset _grab = Offset.zero;
  double _lastScale = 1;
  int _lastPointers = 1;

  /// Whether the gesture moves the map (it had two fingers at some point)
  /// rather than the view.
  bool _movesMap = false;
  _Grip _hover = _Grip.map;
  int _hoverCorner = 0;
  bool _dragging = false;

  /// While resizing: the corner held (0 top left, clockwise) and the
  /// world point of the opposite one, which stays.
  int _corner = 0;
  Offset? _anchor;

  /// The last tap, while a second one would make a double tap.
  Offset? _lastTap;
  Timer? _tapWindow;

  _CanvasMinimapState get _map => widget.state;
  CanvasNavigation get _nav => _map._nav;

  /// How near a corner handle (map pixels) a press takes it.
  double get _cornerReach => Targets.touchFirst ? 14 : 9;

  @override
  void dispose() {
    _tapWindow?.cancel();
    super.dispose();
  }

  /// What a press at [at] on [p] takes hold of (and which corner).
  (_Grip, int) _gripAt(MinimapProjection p, Offset at) {
    final shown = MinimapPainter.viewOnMap(p, _nav.visibleArea);
    if (MinimapPainter.hasHandles(shown)) {
      // A small frame keeps most of itself for moving it.
      final reach = math.min(_cornerReach, shown.shortestSide / 3);
      final corners = [shown.topLeft, shown.topRight, shown.bottomRight, shown.bottomLeft];
      for (var i = 0; i < 4; i++) {
        if ((corners[i] - at).distance <= reach) return (_Grip.corner, i);
      }
    }
    // The view's frame, with some room for a finger.
    if (shown.inflate(MinimapPainter.minView / 2).contains(at)) return (_Grip.frame, 0);
    return (_Grip.map, 0);
  }

  void _tap(TapUpDetails d) {
    final world = _map._projection().toWorld(d.localPosition);
    final last = _lastTap;
    _tapWindow?.cancel();
    if (last != null && (last - d.localPosition).distance <= kDoubleTapSlop / 4) {
      // The second tap: closer there.
      _lastTap = null;
      _nav.zoomInOn(world);
      return;
    }
    _lastTap = d.localPosition;
    _tapWindow = Timer(kDoubleTapTimeout, () => _lastTap = null);
    _nav.centreOn(world);
  }

  void _start(ScaleStartDetails d) {
    _map._hold();
    _lastScale = 1;
    _lastPointers = d.pointerCount;
    _movesMap = d.pointerCount > 1;
    _anchor = null;
    setState(() => _dragging = true);
    if (_movesMap) return;
    final p = _map._projection();
    final at = _down ?? d.localFocalPoint;
    final (grip, corner) = _gripAt(p, at);
    if (grip == _Grip.corner) {
      final view = _nav.visibleArea;
      final corners = [view.topLeft, view.topRight, view.bottomRight, view.bottomLeft];
      _corner = corner;
      _anchor = corners[(corner + 2) % 4];
      return _resize(p, d.localFocalPoint);
    }
    _grab = grip == _Grip.frame ? p.toWorld(at) - _nav.visibleArea.center : Offset.zero;
    _nav.centreOn(p.toWorld(d.localFocalPoint) - _grab, animate: false);
  }

  void _update(ScaleUpdateDetails d) {
    if (d.pointerCount != _lastPointers) {
      // A finger joined or left: the gesture's scale restarts. A second
      // finger turns a drag of the view into moving the map, for good.
      _lastPointers = d.pointerCount;
      _lastScale = d.scale;
      if (d.pointerCount > 1) {
        _movesMap = true;
        _anchor = null;
      }
    }
    if (_movesMap) {
      final factor = d.scale / _lastScale;
      _lastScale = d.scale;
      _map._transform(d.localFocalPoint - d.focalPointDelta, d.localFocalPoint, factor);
    } else if (_anchor != null) {
      _resize(_map._projection(), d.localFocalPoint);
    } else {
      final p = _map._projection();
      _nav.centreOn(p.toWorld(d.localFocalPoint) - _grab, animate: false);
    }
  }

  /// Shows the area from the anchored corner to the finger at [at] (the
  /// view's shape kept, never turned inside out).
  void _resize(MinimapProjection p, Offset at) {
    final anchor = _anchor!;
    final view = _nav.visibleArea;
    final aspect = view.width / view.height;
    final to = p.toWorld(at);
    // The held corner's direction from the anchor.
    final sx = _corner == 1 || _corner == 2 ? 1.0 : -1.0;
    final sy = _corner >= 2 ? 1.0 : -1.0;
    final least = MinimapPainter.minView / p.scale;
    final width = math.max(
      math.max((to.dx - anchor.dx) * sx, (to.dy - anchor.dy) * sy * aspect),
      least,
    );
    final height = width / aspect;
    final far = anchor + Offset(sx * width, sy * height);
    _nav.showArea(Rect.fromPoints(anchor, far), animate: false);
  }

  void _end() {
    _anchor = null;
    _map._release(dragged: !_movesMap);
    if (mounted) setState(() => _dragging = false);
  }

  void _signal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent && event is! PointerScaleEvent) return;
    // Claimed, so nothing beneath scrolls or zooms too.
    GestureBinding.instance.pointerSignalResolver.register(event, (e) {
      final at = e.localPosition;
      switch (e) {
        case PointerScaleEvent(:final scale):
          _map._transform(at, at, scale);
        case PointerScrollEvent(:final scrollDelta):
          final keys = HardwareKeyboard.instance;
          if (keys.isControlPressed || keys.isMetaPressed) {
            const most = PointerNavigation.maxWheelZoomStep;
            final factor = math.exp(-scrollDelta.dy / PointerNavigation.wheelZoomPixels);
            _map._transform(at, at, factor.clamp(1 / most, most));
          } else {
            final across = keys.isShiftPressed && scrollDelta.dx == 0;
            _map._transform(at + (across ? Offset(scrollDelta.dy, 0) : scrollDelta), at);
          }
      }
    });
  }

  /// The chrome around the map, kept clear by its menu.
  EdgeInsets _keepClear = EdgeInsets.zero;

  /// Opens the menu at [at], the press, kept above and left of the map's
  /// far corner: a context menu where you press, but never over the bars
  /// below the map (on a phone, the bottom toolbar).
  void _openMenu(Offset at) {
    setState(() => _keepClear = MinimapMenu.clearOf(context));
    _menu.open(position: at);
  }

  MouseCursor get _cursor {
    if (_dragging) {
      return _anchor != null ? _cornerCursor(_corner) : SystemMouseCursors.grabbing;
    }
    return switch (_hover) {
      _Grip.corner => _cornerCursor(_hoverCorner),
      _Grip.frame => SystemMouseCursors.grab,
      _Grip.map => SystemMouseCursors.click,
    };
  }

  static MouseCursor _cornerCursor(int corner) => corner.isEven
      ? SystemMouseCursors.resizeUpLeftDownRight
      : SystemMouseCursors.resizeUpRightDownLeft;

  @override
  Widget build(BuildContext context) {
    final map = _map;
    return MinimapMenu(
      controller: _menu,
      onHide: map.widget.onHide,
      onFit: map._custom == null ? null : map._fitMap,
      onCollapse: () => map._setCollapsed(true),
      scale: map.widget.scale ?? CanvasMinimap.defaultScale(phone: false),
      onScale: map.widget.onScale,
      keepClear: _keepClear,
      child: Semantics(
        // A node of its own: merged into the editor's focused node, it made
        // the whole editor a tappable "Minimap".
        container: true,
        label: 'Minimap',
        hint: 'Tap to go there, drag to move the view, pinch to zoom the map',
        child: MouseRegion(
          cursor: _cursor,
          onHover: (e) {
            final (grip, corner) = _gripAt(map._projection(), e.localPosition);
            if (grip != _hover || corner != _hoverCorner) {
              setState(() {
                _hover = grip;
                _hoverCorner = corner;
              });
            }
          },
          child: Listener(
            onPointerDown: (e) => _down = e.localPosition,
            onPointerSignal: _signal,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: _tap,
              onScaleStart: _start,
              onScaleUpdate: _update,
              onScaleEnd: (_) => _end(),
              onLongPressStart: (d) => _openMenu(d.localPosition),
              onSecondaryTapUp: (d) => _openMenu(d.localPosition),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
