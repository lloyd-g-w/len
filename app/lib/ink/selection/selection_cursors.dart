import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../viewport.dart';
import 'selection_chrome.dart';
import 'selection_controller.dart';
import 'selection_frame.dart';

/// The mouse cursor over a selection, saying what a press there does (as
/// `LassoTool.down` decides it): a shape's handle or the rotate handle
/// grab, the frame's handles resize along their direction (turned with the
/// frame), the selection itself moves.
abstract final class SelectionCursors {
  /// The cursor at [screen] over [selection], or null off it.
  static MouseCursor? at(
    SelectionController selection,
    ViewportController viewport,
    Offset screen,
  ) {
    final frame = selection.frame;
    if (frame == null || selection.isEmpty) return null;
    final shape = selection.shape;
    if (shape != null &&
        SelectionChrome.shapeHandleAt(
              shape,
              viewport,
              screen,
              frame: frame,
              kind: PointerDeviceKind.mouse,
            ) !=
            null) {
      return SystemMouseCursors.grab;
    }
    final handle = SelectionChrome.hit(frame, viewport, screen, shape: shape);
    if (handle == SelectionHandle.rotate) return SystemMouseCursors.grab;
    if (handle != null) return resize(handle, frame.angle);
    if (SelectionChrome.grabs(frame, viewport, screen, shape: shape)) {
      return SystemMouseCursors.move;
    }
    return null;
  }

  /// The resize cursor for [handle] of a frame turned by [angle] (radians):
  /// the nearest of the four directions.
  static MouseCursor resize(SelectionHandle handle, double angle) {
    final f = handle.fraction;
    final away = Offset((f.dx - 0.5).sign, (f.dy - 0.5).sign);
    // Directions repeat every half turn; four steps of 45°.
    final step = ((away.direction + angle) / (math.pi / 4)).round() % 4;
    return const [
      SystemMouseCursors.resizeLeftRight,
      SystemMouseCursors.resizeUpLeftDownRight,
      SystemMouseCursors.resizeUpDown,
      SystemMouseCursors.resizeUpRightDownLeft,
    ][step];
  }
}
