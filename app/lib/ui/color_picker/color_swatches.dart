import 'package:flutter/material.dart';

/// The preset palette offered by the colour picker: inks, brights and
/// highlighter pastels.
abstract final class ColorSwatches {
  static const List<int> palette = [
    0xFF000000, 0xFF1F2937, 0xFF4B5563, 0xFF9CA3AF, 0xFFFFFFFF, //
    0xFF1E3A8A, 0xFF1C7ED6, 0xFF0EA5E9, 0xFF0CA678, 0xFF2F9E44, //
    0xFF7F1D1D, 0xFFE03131, 0xFFF76707, 0xFFF59F00, 0xFFFACC15, //
    0xFF7048E8, 0xFFC2255C, 0xFFF783AC, 0xFF69DB7C, 0xFF74C0FC, //
  ];
}

/// A small round colour swatch, also used for favourites.
class Swatch extends StatelessWidget {
  const Swatch({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.tooltip,
    this.size = defaultSize,
  });

  static const double defaultSize = 30;

  final double size;

  final int color;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final swatch = GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      onSecondaryTap: onLongPress,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: size,
          height: size,
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: selected ? scheme.primary : Colors.transparent, width: 2),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Color(color),
              shape: BoxShape.circle,
              border: Border.all(color: scheme.outline.withValues(alpha: 0.35)),
            ),
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: '#${(color & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
      child: tooltip == null ? swatch : Tooltip(message: tooltip, child: swatch),
    );
  }
}
