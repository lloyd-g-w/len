import 'package:flutter/material.dart';

import 'canvas_navigation.dart';

/// The "⋮" menu of an infinite canvas: background and navigation.
class CanvasMenu extends StatelessWidget {
  const CanvasMenu({super.key, required this.navigation, required this.onBackground});

  final CanvasNavigation navigation;

  /// Opens the background (template and paper colour) picker.
  final VoidCallback onBackground;

  @override
  Widget build(BuildContext context) {
    final nav = navigation;
    MenuItemButton item(IconData icon, String label, VoidCallback onPressed, {String? hint}) =>
        MenuItemButton(
          leadingIcon: Icon(icon),
          trailingIcon: hint == null ? null : Text(hint),
          onPressed: onPressed,
          child: Text(label),
        );
    return MenuAnchor(
      menuChildren: [
        item(Icons.wallpaper_outlined, 'Background…', onBackground),
        const Divider(),
        item(Icons.fit_screen_outlined, 'Fit content', nav.fitContent, hint: 'Shift+1'),
        item(Icons.crop_free_rounded, 'Actual size (100%)', () => nav.zoomTo(1), hint: '0'),
        item(Icons.home_outlined, 'Back to start', nav.goToOrigin),
        ListenableBuilder(
          listenable: nav,
          builder: (context, _) => item(
            nav.showMinimap ? Icons.map_rounded : Icons.map_outlined,
            nav.showMinimap ? 'Hide overview' : 'Show overview',
            nav.toggleMinimap,
          ),
        ),
      ],
      builder: (context, menu, _) => IconButton(
        tooltip: 'Canvas options',
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
        icon: const Icon(Icons.more_vert_rounded),
      ),
    );
  }
}
