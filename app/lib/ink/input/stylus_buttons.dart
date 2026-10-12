import 'package:flutter/gestures.dart';

import '../../domain/preferences.dart';

/// What a stylus contact does, before the selected tool is consulted.
enum StylusRoute {
  /// Use the selected tool.
  tool,

  /// Erase (eraser end, or the side button set to erase).
  eraser,

  /// Lasso-select (side button set to lasso).
  lasso,
}

/// Stylus buttons that trigger the side-button action while held. Android
/// reports the S Pen side button as [kPrimaryStylusButton]
/// (`MotionEvent.BUTTON_STYLUS_PRIMARY >> 4`); Windows reports the barrel
/// button as primary and the eraser flag as [kSecondaryStylusButton].
const int stylusSideButtons = kPrimaryStylusButton | kSecondaryStylusButton;

/// Whether [kind] is a stylus (either end).
bool isStylusKind(PointerDeviceKind? kind) =>
    kind == PointerDeviceKind.stylus || kind == PointerDeviceKind.invertedStylus;

/// Routes a stylus event by its device kind and held buttons: the eraser end
/// (an inverted stylus) always erases; a held side button does [action].
StylusRoute routeStylus(PointerDeviceKind kind, int buttons, PenButtonAction action) {
  if (kind == PointerDeviceKind.invertedStylus) return StylusRoute.eraser;
  if (kind != PointerDeviceKind.stylus || buttons & stylusSideButtons == 0) {
    return StylusRoute.tool;
  }
  return switch (action) {
    PenButtonAction.eraser => StylusRoute.eraser,
    PenButtonAction.lasso => StylusRoute.lasso,
    PenButtonAction.none => StylusRoute.tool,
  };
}
