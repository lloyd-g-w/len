import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../color_dot.dart';
import '../even_grid.dart';
import '../section_label.dart';

const double _swatchSize = 30;

/// One row of recently picked colours; a tap applies one.
class RecentColorsRow extends StatelessWidget {
  const RecentColorsRow({
    super.key,
    required this.colors,
    required this.selected,
    required this.onTap,
  });

  final List<int> colors;
  final int selected;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Recent'),
        const SizedBox(height: Gaps.xs),
        EvenGrid(
          itemExtent: _swatchSize,
          maxSpacing: Gaps.sm,
          children: [
            for (final c in colors)
              ColorDot(color: c, size: _swatchSize, selected: c == selected, onTap: () => onTap(c)),
          ],
        ),
      ],
    );
  }
}
