import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../navigation/kinetic_pan.dart';
import '../viewport.dart';

/// Pan and zoom from navigating pointers (fingers, middle/right mouse drags),
/// the wheel and the trackpad, for `InkInputController`.
///
/// Pointers that navigate are tracked by id; their centroid pans and their
/// spread about it zooms. [kinetic] adds inertia after a gesture.
class PointerNavigation {
  PointerNavigation({required this.viewport, this.kinetic});

  final ViewportController viewport;

  /// Inertial panning after navigation gestures (optional).
  final KineticPan? kinetic;

  final Map<int, Offset> _pointers = {};
  double _lastPanZoomScale = 1;

  bool get isEmpty => _pointers.isEmpty;

  bool contains(int pointer) => _pointers.containsKey(pointer);

  /// Starts (or restarts) navigating with [pointer] at [position].
  void add(int pointer, Offset position) => _pointers[pointer] = position;

  /// Stops tracking [pointer] (no inertia).
  void remove(int pointer) => _pointers.remove(pointer);

  /// Forgets all navigating pointers (e.g. a stylus landed: they are a palm).
  void clear() => _pointers.clear();

  void move(PointerMoveEvent e) {
    _navigate(e.pointer, e.localPosition);
    kinetic?.track(e.timeStamp);
  }

  /// Lifts [e]'s pointer, releasing inertia when it was the last one.
  void up(PointerUpEvent e) {
    if (_pointers.remove(e.pointer) != null && _pointers.isEmpty) {
      kinetic?.release(e.timeStamp);
    }
  }

  void _navigate(int pointer, Offset position) {
    final before = _pointers.values.toList();
    _pointers[pointer] = position;
    final after = _pointers.values.toList();

    final focalBefore = _centroid(before);
    final focalAfter = _centroid(after);
    viewport.panBy(focalAfter - focalBefore);

    if (after.length >= 2) {
      final spreadBefore = _spread(before, focalBefore);
      final spreadAfter = _spread(after, focalAfter);
      if (spreadBefore > 0) viewport.zoomAt(focalAfter, spreadAfter / spreadBefore);
    }
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
        final keys = HardwareKeyboard.instance;
        if (keys.isControlPressed || keys.isMetaPressed) {
          viewport.zoomAt(e.localPosition, math.exp(-e.scrollDelta.dy / 400));
        } else if (keys.isShiftPressed && e.scrollDelta.dx == 0) {
          viewport.panBy(Offset(-e.scrollDelta.dy, 0));
        } else {
          viewport.panBy(-e.scrollDelta);
        }
      case PointerScaleEvent():
        viewport.zoomAt(e.localPosition, e.scale);
      default:
        break;
    }
  }

  void panZoomStart(PointerPanZoomStartEvent e) {
    _lastPanZoomScale = 1;
    kinetic?.begin();
  }

  void panZoomUpdate(PointerPanZoomUpdateEvent e) {
    viewport.panBy(e.localPanDelta);
    if (e.scale > 0 && e.scale != _lastPanZoomScale) {
      viewport.zoomAt(e.localPosition, e.scale / _lastPanZoomScale);
      _lastPanZoomScale = e.scale;
    }
    kinetic?.track(e.timeStamp);
  }

  void panZoomEnd(PointerPanZoomEndEvent e) => kinetic?.release(e.timeStamp);
}
