part of 'canvas_minimap.dart';

/// The minimap's input. One pointer (touch, pen or mouse) moves the
/// canvas's view: a tap glides it there; a drag moves it live (grabbing the
/// frame keeps the point under the finger, elsewhere centres the view under
/// it). The map itself is moved by everything else, never the canvas: two
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
  bool _overView = false;
  bool _dragging = false;

  _CanvasMinimapState get _map => widget.state;
  CanvasNavigation get _nav => _map._nav;

  /// The view's frame on the map, with some room for a finger.
  bool _onFrame(MinimapProjection p, Offset at) =>
      p.rectToMap(_nav.visibleArea).inflate(MinimapPainter.minView / 2).contains(at);

  void _tap(TapUpDetails d) => _nav.centreOn(_map._projection().toWorld(d.localPosition));

  void _start(ScaleStartDetails d) {
    _map._hold();
    _lastScale = 1;
    _lastPointers = d.pointerCount;
    _movesMap = d.pointerCount > 1;
    setState(() => _dragging = true);
    if (_movesMap) return;
    final p = _map._projection();
    final at = _down ?? d.localFocalPoint;
    _grab = _onFrame(p, at) ? p.toWorld(at) - _nav.visibleArea.center : Offset.zero;
    _nav.centreOn(p.toWorld(d.localFocalPoint) - _grab, animate: false);
  }

  void _update(ScaleUpdateDetails d) {
    if (d.pointerCount != _lastPointers) {
      // A finger joined or left: the gesture's scale restarts. A second
      // finger turns a drag of the view into moving the map, for good.
      _lastPointers = d.pointerCount;
      _lastScale = d.scale;
      if (d.pointerCount > 1) _movesMap = true;
    }
    if (_movesMap) {
      final factor = d.scale / _lastScale;
      _lastScale = d.scale;
      _map._transform(d.localFocalPoint - d.focalPointDelta, d.localFocalPoint, factor);
    } else {
      final p = _map._projection();
      _nav.centreOn(p.toWorld(d.localFocalPoint) - _grab, animate: false);
    }
  }

  void _end() {
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

  @override
  Widget build(BuildContext context) {
    final cursor = _dragging
        ? SystemMouseCursors.grabbing
        : _overView
        ? SystemMouseCursors.grab
        : SystemMouseCursors.click;
    return MinimapMenu(
      controller: _menu,
      onHide: _map.widget.onHide,
      onFit: _map._custom == null ? null : _map._fitMap,
      keepClear: _keepClear,
      child: Semantics(
        // A node of its own: merged into the editor's focused node, it made
        // the whole editor a tappable "Minimap".
        container: true,
        label: 'Minimap',
        hint: 'Tap to go there, drag to move the view, pinch to zoom the map',
        child: MouseRegion(
          cursor: cursor,
          onHover: (e) {
            final over = _onFrame(_map._projection(), e.localPosition);
            if (over != _overView) setState(() => _overView = over);
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
