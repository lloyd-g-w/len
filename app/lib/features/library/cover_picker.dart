import 'package:flutter/material.dart';

import '../../ui/app_theme.dart';
import '../../ui/color_dot.dart';
import '../../ui/even_grid.dart';

/// Colour swatches for choosing a notebook cover.
class CoverPicker extends StatelessWidget {
  const CoverPicker({super.key, required this.color, required this.onColor});

  final int color;
  final ValueChanged<int> onColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = Palette.coverName(color);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: Gaps.sm),
          child: Row(
            children: [
              Text('Colour', style: theme.textTheme.labelLarge),
              if (name != null) ...[
                const SizedBox(width: Gaps.sm),
                Text(name, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
        EvenGrid(
          itemExtent: 40,
          minItemExtent: 32,
          touchTargets: true,
          children: [
            for (var i = 0; i < Palette.covers.length; i++)
              ColorDot(
                color: Palette.covers[i],
                size: 40,
                tooltip: Palette.coverNames[i],
                selected: Palette.covers[i] == color,
                onTap: () => onColor(Palette.covers[i]),
              ),
          ],
        ),
      ],
    );
  }
}
