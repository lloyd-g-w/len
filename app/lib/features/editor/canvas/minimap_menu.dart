import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/preferences.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/menus.dart';

/// The minimap's own menu (long-press or right-click on it): fit it to
/// everything again once zoomed or panned ([onFit]), its size, fold it into
/// its button, hide it (⋯ → View → Minimap or Shift+M brings it back).
class MinimapMenu extends StatelessWidget {
  const MinimapMenu({
    super.key,
    required this.controller,
    required this.child,
    this.onHide,
    this.onFit,
    this.onCollapse,
    this.scale,
    this.onScale,
    this.keepClear = EdgeInsets.zero,
  });

  final MenuController controller;
  final VoidCallback? onHide;

  /// Fits the map to everything again (no row without it).
  final VoidCallback? onFit;

  /// Folds the map into its button.
  final VoidCallback? onCollapse;

  /// The map's size, checked; [onScale] picks another.
  final MinimapScale? scale;
  final ValueChanged<MinimapScale>? onScale;
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

  static const _sizes = {
    MinimapScale.small: 'Small',
    MinimapScale.medium: 'Medium',
    MinimapScale.large: 'Large',
  };

  @override
  Widget build(BuildContext context) => MenuEdgeMargin(
    keepClear: keepClear,
    child: MenuAnchor(
      controller: controller,
      reservedPadding: menuReservedPadding(context),
      menuChildren: [
        if (onFit != null) ...[
          MenuItemButton(
            leadingIcon: const Icon(Symbols.fit_screen_rounded),
            onPressed: onFit,
            child: const Text('Fit minimap'),
          ),
          const Divider(),
        ],
        for (final MapEntry(key: size, value: label) in _sizes.entries)
          MenuItemButton(
            // A leading slot on every row keeps the labels aligned.
            leadingIcon: size == scale
                ? const Icon(Symbols.check_rounded)
                : const SizedBox(width: Glyphs.menu),
            onPressed: onScale == null ? null : () => onScale!(size),
            child: Text(label),
          ),
        const Divider(),
        MenuItemButton(
          leadingIcon: const Icon(Symbols.collapse_content_rounded),
          onPressed: onCollapse,
          child: const Text('Fold minimap'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Symbols.visibility_off_rounded),
          onPressed: onHide,
          child: const Text('Hide minimap'),
        ),
      ],
      child: child,
    ),
  );
}
