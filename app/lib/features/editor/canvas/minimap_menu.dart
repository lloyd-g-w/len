import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/menus.dart';

/// The minimap's own menu (long-press or right-click on it): hide it
/// (⋯ → View → Minimap or Shift+M brings it back).
class MinimapMenu extends StatelessWidget {
  const MinimapMenu({super.key, required this.controller, required this.child, this.onHide});

  final MenuController controller;
  final VoidCallback? onHide;
  final Widget child;

  @override
  Widget build(BuildContext context) => MenuEdgeMargin(
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
