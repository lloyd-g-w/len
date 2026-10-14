import 'package:flutter/material.dart';

import 'color_picker/color_names.dart';
import 'design_tokens.dart';

/// A round colour swatch with a selection ring (colour pickers, cover,
/// folder colours).
class ColorDot extends StatelessWidget {
  const ColorDot({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.size = 32,
    this.target,
    this.tooltip,
    this.child,
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

  /// Side of the square that takes taps, with the dot centred in it
  /// (defaults to [size]). A parent's tight constraints (a grid cell)
  /// override it: then the whole cell takes taps.
  final double? target;

  /// Optional tooltip; also the accessibility label (else the colour's
  /// name, [colorName]).
  final String? tooltip;

  /// Drawn centred on the swatch (a "none" glyph).
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dot = Semantics(
      button: true,
      selected: selected,
      label: tooltip ?? colorName(color),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onLongPress: onLongPress,
          onSecondaryTap: onLongPress,
          child: SizedBox.square(
            dimension: target ?? size,
            child: Center(child: _dot(scheme)),
          ),
        ),
      ),
    );
    return tooltip == null ? dot : Tooltip(message: tooltip, child: dot);
  }

  Widget _dot(ColorScheme scheme) => AnimatedContainer(
    duration: Motion.fast,
    width: size,
    height: size,
    // Ring and gap scale with the dot (2.5 + 3 at the default size).
    padding: EdgeInsets.all(size * 0.09),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(
        color: selected ? scheme.onSurface : Colors.transparent,
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
      child: child == null ? null : Center(child: child),
    ),
  );

  bool _nearSurface(ColorScheme scheme) =>
      (Color(color).computeLuminance() - scheme.surface.computeLuminance()).abs() < 0.08;
}
