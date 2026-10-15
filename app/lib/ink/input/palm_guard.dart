import 'package:flutter/gestures.dart';

import 'stylus_buttons.dart';
import 'stylus_proximity.dart';

/// Palm rejection beyond a single canvas: watches every pointer event of
/// the app through a global route of the gesture binding once [attach]ed
/// (tests feed [handleEvent] directly).
///
/// - While a stylus touches the screen, touches are the writing hand's
///   palm wherever they land — on a toolbar button, the page indicator,
///   the Add page footer, the other split pane: they are cancelled, so
///   lifting the palm taps nothing. Touches already down when the pen
///   lands are cancelled too. A finger tapping chrome while the pen only
///   hovers still works (the other hand on Undo).
/// - Canvases ask [stylusNear] for the pen anywhere in the app, so a palm
///   resting on one pane while the pen hovers over the other neither pans
///   nor draws there.
class PalmGuard {
  PalmGuard({void Function(int pointer)? cancel}) : _cancelOverride = cancel;

  final void Function(int pointer)? _cancelOverride;
  final StylusProximity _stylus = StylusProximity();
  final Set<int> _touches = {};
  int? _pen;
  PointerRouter? _router;

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
    _touches.clear();
    _pen = null;
  }

  /// Whether a stylus touches the screen, or was seen (touching or
  /// hovering) within [within] before [time].
  bool stylusNear(Duration time, {required Duration within}) =>
      _stylus.isNear(time, within: within);

  /// Records [e], cancelling it if it is a palm.
  void handleEvent(PointerEvent e) {
    if (isStylusKind(e.kind)) {
      _stylus.note(e);
      switch (e) {
        case PointerDownEvent():
          _pen = e.pointer;
          _touches.toList().forEach(_cancel);
          _touches.clear();
        case PointerUpEvent() || PointerCancelEvent() when e.pointer == _pen:
          _pen = null;
        default:
      }
      return;
    }
    if (e.kind != PointerDeviceKind.touch) return;
    switch (e) {
      case PointerDownEvent() when _pen != null:
        _cancel(e.pointer);
      case PointerDownEvent():
        _touches.add(e.pointer);
      case PointerUpEvent() || PointerCancelEvent():
        _touches.remove(e.pointer);
      default:
    }
  }

  void _cancel(int pointer) =>
      (_cancelOverride ?? GestureBinding.instance.cancelPointer).call(pointer);
}
