import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/color_dot.dart';
import '../../../ui/roving_focus.dart';

/// The ten cover colours in one row, the dots sized to the width; two rows
/// of five on touch where one row would shrink the targets under
/// [Targets.touch] (phones).
class CoverRow extends StatelessWidget {
  const CoverRow({super.key, required this.color, required this.onColor});

  final int color;
  final ValueChanged<int> onColor;

  @override
  Widget build(BuildContext context) {
    final colors = Palette.covers;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final perRow = Targets.touchFirst && width / colors.length < Targets.touch
            ? (colors.length / 2).ceil()
            : colors.length;
        final twoRows = perRow < colors.length;
        final cell = math.min(Targets.touchFirst ? Targets.touch : 44.0, width / perRow);
        Widget dot(int i) => ColorDot(
          key: ValueKey('cover-$i'),
          color: colors[i],
          size: math.min(34, cell - Gaps.xs),
          target: cell,
          tooltip: Palette.coverNames[i],
          selected: colors[i] == color,
          onTap: () => onColor(colors[i]),
        );
        // One Tab stop, at the chosen colour; the arrows move inside.
        return RovingGroup.grid(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var start = 0; start < colors.length; start += perRow)
                Row(
                  // Two rows spread across the width.
                  mainAxisAlignment: twoRows
                      ? MainAxisAlignment.spaceBetween
                      : MainAxisAlignment.start,
                  children: [
                    for (var i = start; i < math.min(start + perRow, colors.length); i++) dot(i),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}
