import 'package:flutter/gestures.dart';

import 'input_recording.dart';

/// Rebuilds the pointer event a [PointerEntry] recorded, transformed into
/// the drawing surface's local space exactly as its `Listener` delivered it.
PointerEvent pointerEventOf(PointerEntry e) {
  final timeStamp = Duration(microseconds: e.timeStampUs);
  final PointerEvent event = switch (e.type) {
    PointerType.down => PointerDownEvent(
      timeStamp: timeStamp,
      pointer: e.pointer,
      kind: e.kind,
      device: e.device,
      position: e.position,
      buttons: e.buttons,
      pressure: e.pressure,
      pressureMin: e.pressureMin,
      pressureMax: e.pressureMax,
      tilt: e.tilt,
      orientation: e.orientation,
    ),
    PointerType.move => PointerMoveEvent(
      timeStamp: timeStamp,
      pointer: e.pointer,
      kind: e.kind,
      device: e.device,
      position: e.position,
      buttons: e.buttons,
      pressure: e.pressure,
      pressureMin: e.pressureMin,
      pressureMax: e.pressureMax,
      tilt: e.tilt,
      orientation: e.orientation,
      synthesized: e.synthesized,
    ),
    PointerType.up => PointerUpEvent(
      timeStamp: timeStamp,
      pointer: e.pointer,
      kind: e.kind,
      device: e.device,
      position: e.position,
      buttons: e.buttons,
      pressure: e.pressure,
      pressureMin: e.pressureMin,
      pressureMax: e.pressureMax,
      tilt: e.tilt,
      orientation: e.orientation,
    ),
    PointerType.cancel => PointerCancelEvent(
      timeStamp: timeStamp,
      pointer: e.pointer,
      kind: e.kind,
      device: e.device,
      position: e.position,
      buttons: e.buttons,
    ),
    PointerType.hover => PointerHoverEvent(
      timeStamp: timeStamp,
      kind: e.kind,
      device: e.device,
      position: e.position,
      buttons: e.buttons,
      tilt: e.tilt,
      orientation: e.orientation,
      synthesized: e.synthesized,
    ),
  };
  final shift = e.localPosition - e.position;
  if (shift == Offset.zero) return event;
  return event.transformed(Matrix4.translationValues(shift.dx, shift.dy, 0));
}
