import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/color_dot.dart';

/// The ten cover colours in one row, the dots sized to the width.
class CoverRow extends StatelessWidget {
  const CoverRow({super.key, required this.color, required this.onColor});

  final int color;
  final ValueChanged<int> onColor;

  @override
  Widget build(BuildContext context) {
    final colors = Palette.covers;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cell = math.min(44.0, constraints.maxWidth / colors.length);
        return Row(
          children: [
            for (var i = 0; i < colors.length; i++)
              ColorDot(
                key: ValueKey('cover-$i'),
                color: colors[i],
                size: math.min(34, cell - Gaps.xs),
                target: cell,
                tooltip: Palette.coverNames[i],
                selected: colors[i] == color,
                onTap: () => onColor(colors[i]),
              ),
          ],
        );
      },
    );
  }
}
