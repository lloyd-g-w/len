import 'package:flutter/material.dart';

import '../../../ui/app_theme.dart';

/// An icon button of the editor's top bar: a 20-dp glyph on a 40-dp
/// button (48-dp hit area on touch), quiet by default, on the neutral
/// plate and filled when [selected].
class BarButton extends StatelessWidget {
  const BarButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    this.selectedIcon,
    this.color,
  });

  /// The glyph's colour when not selected (default Graphite).
  final Color? color;

  final IconData icon;
  final IconData? selectedIcon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      isSelected: selected,
      iconSize: Glyphs.bar,
      style: IconButton.styleFrom(
        foregroundColor: selected ? scheme.onSurface : color ?? scheme.onSurfaceVariant,
        backgroundColor: selected ? Surfaces.pressed(scheme) : null,
        minimumSize: const Size.square(Targets.bar),
        fixedSize: const Size.square(Targets.bar),
        padding: EdgeInsets.zero,
        // A 48-dp hit area on touch, the 40-dp visual with a pointer.
        tapTargetSize: Targets.touchFirst
            ? MaterialTapTargetSize.padded
            : MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(icon),
      selectedIcon: Icon(selectedIcon ?? icon, fill: 1),
    );
  }
}
