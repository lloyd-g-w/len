import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/menus.dart';

/// The minimap's own menu (long-press or right-click on it): hide it
/// (⋯ → View → Minimap or Shift+M brings it back).
class MinimapMenu extends StatelessWidget {
  const MinimapMenu({
    super.key,
    required this.controller,
    required this.child,
    this.onHide,
    this.keepClear = EdgeInsets.zero,
  });

  final MenuController controller;
  final VoidCallback? onHide;
  final Widget child;

  /// Room at the screen's edges the menu stays out of, beside the safe
  /// area: the chrome around the map ([clearOf]).
  final EdgeInsets keepClear;

  /// The room below and to the right of [map] (the map's own context) on
  /// the screen: the map sits in the canvas's bottom-right corner, clear
  /// of the chrome, so a menu kept above and left of its far corner never
  /// covers a bar (a phone's bottom toolbar, the audio strip).
  static EdgeInsets clearOf(BuildContext map) {
    final box = map.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(map).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null || !box.attached) return EdgeInsets.zero;
    final corner = box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay);
    return EdgeInsets.only(
      right: math.max(0, overlay.size.width - corner.dx),
      bottom: math.max(0, overlay.size.height - corner.dy),
    );
  }

  @override
  Widget build(BuildContext context) => MenuEdgeMargin(
    keepClear: keepClear,
    child: MenuAnchor(
      controller: controller,
      reservedPadding: menuReservedPadding(context),
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Symbols.visibility_off_sharp),
          onPressed: onHide,
          child: const Text('Hide minimap'),
        ),
      ],
      child: child,
    ),
  );
}
