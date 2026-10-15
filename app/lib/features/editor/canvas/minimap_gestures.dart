part of 'canvas_minimap.dart';

/// The minimap's input, for touch, pen and mouse alike: a tap glides the
/// view there; a drag moves it live (grabbing the frame keeps the point
/// under the finger, elsewhere centres the view under it); two fingers
/// pinch to zoom and move; a mouse wheel zooms in steps; long-press or
/// right-click opens the menu.
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
  bool _overView = false;
  bool _dragging = false;

  _CanvasMinimapState get _map => widget.state;
  CanvasNavigation get _nav => _map._nav;

  /// The view's frame on the map, with some room for a finger.
  bool _onFrame(MinimapProjection p, Offset at) =>
      p.rectToMap(_nav.visibleArea).inflate(MinimapPainter.minView / 2).contains(at);

  void _tap(TapUpDetails d) => _nav.centreOn(_map._projection().toWorld(d.localPosition));

  void _start(ScaleStartDetails d) {
    final p = _map._projection();
    _map._held = p;
    _lastScale = 1;
    _lastPointers = d.pointerCount;
    setState(() => _dragging = true);
    if (d.pointerCount > 1) return;
    final at = _down ?? d.localFocalPoint;
    _grab = _onFrame(p, at) ? p.toWorld(at) - _nav.visibleArea.center : Offset.zero;
    _nav.centreOn(p.toWorld(d.localFocalPoint) - _grab, animate: false);
  }

  void _update(ScaleUpdateDetails d) {
    final p = _map._held ?? _map._projection();
    if (d.pointerCount != _lastPointers) {
      // A finger joined or left: the gesture's scale restarts.
      _lastPointers = d.pointerCount;
      _lastScale = d.scale;
      _grab = p.toWorld(d.localFocalPoint) - _nav.visibleArea.center;
    }
    if (d.pointerCount > 1) {
      _nav.centreOn(_nav.visibleArea.center + d.focalPointDelta / p.scale, animate: false);
      if (d.scale != _lastScale) _nav.zoomBy(d.scale / _lastScale);
      _lastScale = d.scale;
    } else {
      _nav.centreOn(p.toWorld(d.localFocalPoint) - _grab, animate: false);
    }
  }

  void _end() {
    if (_map._held case final held?) {
      _map
        .._held = null
        .._from = null
        .._to = held.world
        .._onView();
    }
    if (mounted) setState(() => _dragging = false);
  }

  void _signal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) return;
    // Claimed, so nothing beneath scrolls too.
    GestureBinding.instance.pointerSignalResolver.register(event, (e) {
      _nav.zoomStep((e as PointerScrollEvent).scrollDelta.dy < 0 ? 1 : -1);
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
      keepClear: _keepClear,
      child: Semantics(
        // A node of its own: merged into the editor's focused node, it made
        // the whole editor a tappable "Minimap".
        container: true,
        label: 'Minimap',
        hint: 'Tap to go there, drag to move',
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
