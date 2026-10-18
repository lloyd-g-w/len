import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/menus.dart';
import '../editor_session.dart';

/// What the zoom box's ⋯ menu offers.
enum ZoomBoxChoice { leftHanded, rightToLeft, automaticHeight }

/// The box's own menu: left-handed (the box docks at the top, so the
/// writing arm hides none of the page), right to left (lines advance
/// leftwards; at first as the device's language runs), and the automatic
/// height once one was dragged.
List<PopupMenuEntry<ZoomBoxChoice>> zoomBoxMenu(EditorSession session) => [
  MenuRow(
    value: ZoomBoxChoice.leftHanded,
    icon: Symbols.front_hand_sharp,
    label: 'Left-handed',
    caption: 'Box at the top',
    checked: session.services.preferences.zoomBoxAtTop,
  ),
  MenuRow(
    value: ZoomBoxChoice.rightToLeft,
    icon: Symbols.format_textdirection_r_to_l_sharp,
    label: 'Right to left',
    caption: 'Lines advance leftwards',
    checked: session.services.preferences.zoomWritesRightToLeft,
  ),
  if (session.zoomWindow.boxHeight.value != null)
    const MenuRow(
      value: ZoomBoxChoice.automaticHeight,
      icon: Symbols.height_sharp,
      label: 'Automatic height',
    ),
];

/// Does [choice] from [zoomBoxMenu].
void onZoomBoxMenu(EditorSession session, ZoomBoxChoice choice) {
  switch (choice) {
    case ZoomBoxChoice.leftHanded:
      final prefs = session.services.preferences;
      prefs.zoomBoxAtTop = !prefs.zoomBoxAtTop;
      // Once the editor made room for the box at its new edge.
      WidgetsBinding.instance.addPostFrameCallback((_) => session.zoomWindow.showFrame());
    case ZoomBoxChoice.rightToLeft:
      session.services.preferences.toggleZoomRightToLeft();
      session.zoomWindow.directionChanged();
    case ZoomBoxChoice.automaticHeight:
      session.zoomWindow.boxHeight.value = null;
  }
}
