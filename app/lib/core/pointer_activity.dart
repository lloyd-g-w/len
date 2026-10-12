import 'package:flutter/gestures.dart';

/// Whether the user is touching the app right now — a pen or finger down
/// (writing, scrolling, pinch-zooming), a trackpad pan/zoom, a stylus
/// hovering — and when that last happened, so background work (handwriting
/// recognition) can keep off the UI thread meanwhile.
///
/// Watches every pointer event through a global route of the gesture
/// binding once [attach]ed; tests feed [handleEvent] directly.
class PointerActivity {
  PointerActivity({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final _down = <int>{};
  final _panZooms = <int>{};
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  PointerRouter? _router;

  /// Whether a pointer is down or a trackpad gesture is in progress.
  bool get isActive => _down.isNotEmpty || _panZooms.isNotEmpty;

  /// When the last pointer event that counts as activity arrived (or now,
  /// while [isActive]).
  DateTime get lastActivity => isActive ? _now() : _last;

  /// Starts watching the app's pointer events.
  void attach([PointerRouter? router]) {
    if (_router != null) return;
    _router = router ?? GestureBinding.instance.pointerRouter;
    _router!.addGlobalRoute(handleEvent);
  }

  /// Stops watching (and forgets pointers that are down).
  void detach() {
    _router?.removeGlobalRoute(handleEvent);
    _router = null;
    _down.clear();
    _panZooms.clear();
  }

  /// Records [event].
  void handleEvent(PointerEvent event) {
    switch (event) {
      case PointerDownEvent():
        _down.add(event.pointer);
      case PointerUpEvent() || PointerCancelEvent():
        _down.remove(event.pointer);
      case PointerPanZoomStartEvent():
        _panZooms.add(event.pointer);
      case PointerPanZoomEndEvent():
        _panZooms.remove(event.pointer);
      case PointerMoveEvent() || PointerPanZoomUpdateEvent() || PointerSignalEvent():
        break;
      case PointerHoverEvent(kind: PointerDeviceKind.stylus || PointerDeviceKind.invertedStylus):
        // A pen hovering is about to write.
        break;
      default:
        return; // Mouse hovers and the like are not interaction.
    }
    _last = _now();
  }
}
