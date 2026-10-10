import 'package:flutter/material.dart';

/// A round colour swatch with a selection ring.
class ColorDot extends StatelessWidget {
  const ColorDot({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
    this.size = 32,
    this.tooltip,
  });

  final int color;
  final bool selected;
  final VoidCallback onTap;
  final double size;

  /// Optional tooltip / accessibility label.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dot = Semantics(
      button: true,
      selected: selected,
      label: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: size,
            height: size,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: selected ? scheme.primary : Colors.transparent, width: 2.5),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(color),
                shape: BoxShape.circle,
                // Keeps dark swatches visible on dark chrome and light ones on light.
                border: Border.all(color: scheme.outline.withValues(alpha: 0.35)),
              ),
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? dot : Tooltip(message: tooltip, child: dot);
  }
}
