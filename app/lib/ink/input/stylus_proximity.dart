import 'package:flutter/gestures.dart';

/// Where the pen is, for palm rejection: touching the screen, or when it
/// was last seen (touching or hovering). A hand writing rests its palm
/// while the pen is near — between strokes the pen only lifts briefly, and
/// a hovering pen streams hover events.
class StylusProximity {
  bool _down = false;
  Duration? _lastSeen;

  /// Notes [e] if it comes from a stylus (either end).
  void note(PointerEvent e) {
    if (e.kind != PointerDeviceKind.stylus && e.kind != PointerDeviceKind.invertedStylus) return;
    _lastSeen = e.timeStamp;
    _down = switch (e) {
      PointerDownEvent() || PointerMoveEvent() => true,
      PointerUpEvent() || PointerCancelEvent() || PointerHoverEvent() => false,
      _ => _down,
    };
  }

  /// Whether the pen touches, or was seen within [within] before [time].
  bool isNear(Duration time, {required Duration within}) {
    final last = _lastSeen;
    return _down || (last != null && time - last < within);
  }
}
