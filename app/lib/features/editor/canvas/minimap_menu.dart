import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_switch.dart';
import '../../../ui/menus.dart';

/// The minimap's own menu (long-press or right-click on it): keep it in
/// focus mode, or hide it.
class MinimapMenu extends StatelessWidget {
  const MinimapMenu({
    super.key,
    required this.controller,
    required this.pinned,
    required this.child,
    this.onPinned,
    this.onHide,
  });

  final MenuController controller;
  final bool pinned;
  final ValueChanged<bool>? onPinned;
  final VoidCallback? onHide;
  final Widget child;

  @override
  Widget build(BuildContext context) => MenuEdgeMargin(
    child: MenuAnchor(
      controller: controller,
      reservedPadding: menuReservedPadding(context),
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Symbols.keep_sharp),
          trailingIcon: IgnorePointer(
            child: ExcludeFocus(
              child: AppSwitch(value: pinned, onChanged: (_) {}, padded: false),
            ),
          ),
          onPressed: onPinned == null ? null : () => onPinned!(!pinned),
          child: const Text('Keep in focus mode'),
        ),
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
