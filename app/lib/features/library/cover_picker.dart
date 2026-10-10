import 'package:flutter/material.dart';

import '../../domain/cover_style.dart';
import '../../domain/notebook.dart';
import '../../ui/app_theme.dart';
import '../../ui/color_dot.dart';
import 'cover_pattern_painter.dart';

/// Colour swatches plus pattern tiles for choosing a notebook cover.
class CoverPicker extends StatelessWidget {
  const CoverPicker({
    super.key,
    required this.color,
    required this.style,
    required this.kind,
    required this.onColor,
    required this.onStyle,
  });

  final int color;
  final CoverStyle style;
  final NotebookKind kind;
  final ValueChanged<int> onColor;
  final ValueChanged<CoverStyle> onStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: Gaps.xs,
          runSpacing: Gaps.xs,
          children: [
            for (final c in Palette.covers)
              ColorDot(color: c, size: 36, selected: c == color, onTap: () => onColor(c)),
          ],
        ),
        const SizedBox(height: Gaps.lg),
        Text('Pattern', style: theme.textTheme.labelLarge),
        const SizedBox(height: Gaps.sm),
        Wrap(
          spacing: Gaps.sm,
          runSpacing: Gaps.sm,
          children: [
            for (final s in CoverStyle.values)
              _PatternTile(color: color, style: s, selected: s == style, onTap: () => onStyle(s)),
          ],
        ),
      ],
    );
  }
}

class _PatternTile extends StatelessWidget {
  const _PatternTile({
    required this.color,
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final int color;
  final CoverStyle style;
  final bool selected;
  final VoidCallback onTap;

  static String label(CoverStyle s) => switch (s) {
    CoverStyle.plain => 'Plain',
    CoverStyle.linen => 'Linen',
    CoverStyle.dots => 'Dots',
    CoverStyle.grid => 'Grid',
    CoverStyle.waves => 'Waves',
    CoverStyle.stripes => 'Stripes',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: label(style),
      child: Semantics(
        button: true,
        selected: selected,
        label: '${label(style)} pattern',
        child: GestureDetector(
          onTap: onTap,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: AnimatedContainer(
              duration: Motion.fast,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.sm + 3),
                border: Border.all(color: selected ? scheme.primary : Colors.transparent, width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Radii.sm),
                child: SizedBox(
                  width: 40,
                  height: 52,
                  child: ColoredBox(
                    color: Color(color),
                    child: CustomPaint(painter: CoverPatternPainter(style, opacity: 0.3)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
