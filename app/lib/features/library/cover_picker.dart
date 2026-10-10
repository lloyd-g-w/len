import 'package:flutter/material.dart';

import '../../domain/cover_style.dart';
import '../../domain/notebook.dart';
import '../../ui/app_theme.dart';
import '../../ui/color_dot.dart';
import 'notebook_cover.dart';

/// Colour swatches plus a gallery of covers (every pattern in the chosen
/// colour) for choosing a notebook cover.
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

  /// Human-readable name of a cover pattern.
  static String styleLabel(CoverStyle s) => switch (s) {
    CoverStyle.plain => 'Plain',
    CoverStyle.linen => 'Linen',
    CoverStyle.dots => 'Dots',
    CoverStyle.grid => 'Grid',
    CoverStyle.waves => 'Waves',
    CoverStyle.stripes => 'Stripes',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget label(String text, String? detail) => Padding(
      padding: const EdgeInsets.only(bottom: Gaps.sm),
      child: Row(
        children: [
          Text(text, style: theme.textTheme.titleSmall),
          if (detail != null) ...[
            const SizedBox(width: Gaps.sm),
            Text(detail, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        label('Colour', Palette.coverName(color)),
        Wrap(
          spacing: Gaps.xs,
          runSpacing: Gaps.xs,
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
        const SizedBox(height: Gaps.xl),
        label('Style', styleLabel(style)),
        Wrap(
          spacing: Gaps.sm,
          runSpacing: Gaps.md,
          children: [
            for (final s in CoverStyle.values)
              _CoverTile(
                color: color,
                style: s,
                kind: kind,
                selected: s == style,
                onTap: () => onStyle(s),
              ),
          ],
        ),
      ],
    );
  }
}

/// A miniature cover in one pattern, with its name.
class _CoverTile extends StatelessWidget {
  const _CoverTile({
    required this.color,
    required this.style,
    required this.kind,
    required this.selected,
    required this.onTap,
  });

  final int color;
  final CoverStyle style;
  final NotebookKind kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = CoverPicker.styleLabel(style);
    return Semantics(
      button: true,
      selected: selected,
      label: '$name cover',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.control),
        child: Padding(
          padding: const EdgeInsets.all(Gaps.xxs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: Motion.fast,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.cover + 3),
                  border: Border.all(
                    color: selected ? scheme.primary : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Container(
                  width: 56,
                  height: 76,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Radii.cover),
                    boxShadow: Shadows.low(theme.brightness),
                  ),
                  child: NotebookCover(color: color, style: style, kind: kind),
                ),
              ),
              const SizedBox(height: Gaps.xs),
              Text(
                name,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
