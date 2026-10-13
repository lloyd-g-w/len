import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../navigation/kinetic_pan.dart';
import '../viewport.dart';

/// Pan and zoom from navigating pointers (fingers, middle/right mouse drags),
/// the wheel and the trackpad, for `InkInputController`.
///
/// Pointers that navigate are tracked by id; their centroid pans and their
/// spread about it zooms, so the point under the fingers stays under them.
/// Like native scroll views, a gesture only starts moving the view once a
/// pointer travels past its slop (taps and resting fingers never nudge it),
/// and only zooms once the fingers' spread changes by [spreadSlop] (a
/// two-finger pan never drifts in zoom). Past the zoom limits a pinch
/// stretches the zoom ([ViewportController.stretchAt]); [kinetic] finishes
/// gestures: settling, spring back, inertia.
class PointerNavigation {
  PointerNavigation({required this.viewport, this.kinetic});

  final ViewportController viewport;

  /// Inertia and settling after navigation gestures (optional).
  final KineticPan? kinetic;

  /// How far (logical pixels) the fingers' spread must change before a
  /// gesture zooms.
  static const double spreadSlop = 8;

  /// Ctrl+wheel zoom: one event zooms by `exp(-dy / wheelZoomPixels)`.
  static const double wheelZoomPixels = 400;

  /// Largest zoom step of one wheel event (a fast spin, a bad device).
  static const double maxWheelZoomStep = 2;

  final Map<int, Offset> _pointers = {};
  final Map<int, ({Offset at, double slop})> _starts = {};
  bool _panning = false;
  bool _zooming = false;
  double _spreadAnchor = 0;

  /// The zoom the fingers ask for; past the limits the view shows it
  /// stretched.
  double _wanted = 1;
  Offset _focal = Offset.zero;

  double _panZoomStartScale = 1;
  bool _panZoomZoomed = false;

  bool get isEmpty => _pointers.isEmpty;

  bool contains(int pointer) => _pointers.containsKey(pointer);

  /// Whether the current gesture moves the view (it went past the slop):
  /// it is a pan or a pinch, not a tap or a long press.
  bool get moving => _panning;

  /// Starts navigating with [pointer] at [position]. Until the gesture
  /// moves the view, this pointer starts it once it travels further than
  /// [slop] (fingers; 0 for mouse drags).
  void add(int pointer, Offset position, {double slop = 0}) {
    if (_pointers.isEmpty) {
      _panning = false;
      _zooming = false;
    }
    _pointers[pointer] = position;
    _starts[pointer] = (at: position, slop: slop);
    _anchorSpread();
  }

  /// Forgets all navigating pointers (e.g. a stylus landed: they are a palm).
  void clear() {
    _pointers.clear();
    _starts.clear();
  }

  void move(PointerMoveEvent e) {
    final to = e.localPosition;
    var from = _pointers[e.pointer] ?? to;
    _pointers[e.pointer] = to;
    if (!_panning) {
      final start = _starts[e.pointer];
      final travel = start == null ? 0.0 : (to - start.at).distance;
      if (start == null || travel <= start.slop) {
        if (!_pinching) return;
        // The spread changed first: zoom from the next move on.
        _panning = true;
        _startZoom();
        return;
      }
      _panning = true;
      if (_pinching) _startZoom();
      // Move on from the edge of the slop: the view lags the finger by the
      // slop instead of jumping.
      from = Offset.lerp(start.at, to, start.slop / travel)!;
    } else if (!_zooming && _pinching) {
      _startZoom();
    }
    _apply(e.pointer, from);
    _focal = _centroid(_pointers.values.toList());
    kinetic?.track(e.timeStamp);
  }

  /// Pans by how far the centroid moved when [pointer] moved from [from]
  /// to where it is now, and zooms by how the spread changed (about the
  /// centroid, so the point under the fingers stays under them).
  void _apply(int pointer, Offset from) {
    final after = _pointers.values.toList();
    final before = [for (final p in _pointers.entries) p.key == pointer ? from : p.value];
    final focalBefore = _centroid(before);
    final focalAfter = _centroid(after);
    viewport.panBy(focalAfter - focalBefore);
    if (!_zooming || after.length < 2) return;
    final spreadBefore = _spread(before, focalBefore);
    if (spreadBefore <= 0) return;
    _wanted *= _spread(after, focalAfter) / spreadBefore;
    viewport.stretchAt(focalAfter, _wanted);
  }

  /// Whether the fingers' spread changed past [spreadSlop] since the set
  /// of fingers last changed.
  bool get _pinching {
    final points = _pointers.values.toList();
    if (points.length < 2) return false;
    return (_spread(points, _centroid(points)) - _spreadAnchor).abs() > spreadSlop;
  }

  void _startZoom() {
    _zooming = true;
    _wanted = viewport.inelastic(viewport.scale);
  }

  /// Lifts [e]'s pointer; the gesture ends (settling, inertia) when it was
  /// the last one.
  void up(PointerUpEvent e) => _lift(e);

  /// The platform cancelled [e]'s pointer: like lifting it (a stretched
  /// zoom still springs back).
  void cancel(PointerCancelEvent e) => _lift(e);

  void _lift(PointerEvent e) {
    if (_pointers.remove(e.pointer) == null) return;
    _starts.remove(e.pointer);
    _anchorSpread();
    if (_pointers.isEmpty) kinetic?.release(e.timeStamp, focal: _focal, zoomed: _zooming);
  }

  /// A pinch is measured from the spread the fingers have when the set of
  /// fingers changes.
  void _anchorSpread() {
    final points = _pointers.values.toList();
    if (points.length >= 2) _spreadAnchor = _spread(points, _centroid(points));
  }

  static Offset _centroid(List<Offset> points) =>
      points.reduce((a, b) => a + b) / points.length.toDouble();

  static double _spread(List<Offset> points, Offset centre) =>
      points.map((p) => (p - centre).distance).reduce((a, b) => a + b) / points.length;

  // ---------------------------------------------------------------------------
  // Wheel / trackpad

  void signal(PointerSignalEvent e) {
    switch (e) {
      case PointerScrollEvent():
        kinetic?.begin(); // The wheel takes over from a glide.
        final keys = HardwareKeyboard.instance;
        if (keys.isControlPressed || keys.isMetaPressed) {
          final factor = math.exp(-e.scrollDelta.dy / wheelZoomPixels);
          const most = maxWheelZoomStep;
          viewport.zoomAt(e.localPosition, factor.clamp(1 / most, most));
        } else if (keys.isShiftPressed && e.scrollDelta.dx == 0) {
          viewport.panBy(Offset(-e.scrollDelta.dy, 0));
        } else {
          viewport.panBy(-e.scrollDelta);
        }
      case PointerScaleEvent():
        viewport.zoomAt(e.localPosition, e.scale);
      case PointerScrollInertiaCancelEvent():
        kinetic?.begin(); // Fingers back on the trackpad catch a glide.
      default:
        break;
    }
  }

  void panZoomStart(PointerPanZoomStartEvent e) {
    _panZoomStartScale = viewport.inelastic(viewport.scale);
    _panZoomZoomed = false;
    kinetic?.begin();
  }

  /// Trackpad pan and pinch: [PointerPanZoomUpdateEvent.scale] is the
  /// pinch's total, so the zoom follows the fingers exactly (stretched past
  /// the limits), about the cursor.
  void panZoomUpdate(PointerPanZoomUpdateEvent e) {
    viewport.panBy(e.localPanDelta);
    if (e.scale > 0 && e.scale.isFinite && (_panZoomZoomed || e.scale != 1)) {
      _panZoomZoomed = true;
      viewport.stretchAt(e.localPosition, _panZoomStartScale * e.scale);
    }
    kinetic?.track(e.timeStamp);
  }

  void panZoomEnd(PointerPanZoomEndEvent e) =>
      kinetic?.release(e.timeStamp, focal: e.localPosition, zoomed: _panZoomZoomed);
}
