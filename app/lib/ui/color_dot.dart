import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// A round colour swatch with a selection ring (colour pickers, cover,
/// folder and accent colours).
class ColorDot extends StatelessWidget {
  const ColorDot({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.size = 32,
    this.tooltip,
  });

  /// ARGB colour shown.
  final int color;

  /// Draws the selection ring.
  final bool selected;

  final VoidCallback onTap;

  /// Long press (or right-click), e.g. to remove a favourite.
  final VoidCallback? onLongPress;

  /// Outer diameter, ring included.
  final double size;

  /// Optional tooltip; also the accessibility label (else the hex code).
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dot = Semantics(
      button: true,
      selected: selected,
      label: tooltip ?? '#${(color & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          onLongPress: onLongPress,
          onSecondaryTap: onLongPress,
          child: AnimatedContainer(
            duration: Motion.fast,
            width: size,
            height: size,
            // Ring and gap scale with the dot (2.5 + 3 at the default size).
            padding: EdgeInsets.all(size * 0.09),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? scheme.primary : Colors.transparent,
                width: size * 0.075,
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(color),
                shape: BoxShape.circle,
                // Keeps dark swatches visible on dark chrome and light ones on
                // light: a firmer ring when the swatch is close to the surface.
                border: Border.all(
                  color: scheme.outline.withValues(alpha: _nearSurface(scheme) ? 0.9 : 0.35),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? dot : Tooltip(message: tooltip, child: dot);
  }

  bool _nearSurface(ColorScheme scheme) =>
      (Color(color).computeLuminance() - scheme.surface.computeLuminance()).abs() < 0.08;
}
