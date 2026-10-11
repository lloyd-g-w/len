import 'package:flutter/material.dart';

import '../../../domain/paper.dart';
import '../../../ui/app_theme.dart';
import '../template_preview.dart';

/// Templates grouped the way people look for them.
const List<(String, List<PaperStyle>)> templateGroups = [
  ('Basic', [PaperStyle.blank, PaperStyle.dotted]),
  (
    'Lined',
    [PaperStyle.narrowRuled, PaperStyle.collegeRuled, PaperStyle.wideRuled, PaperStyle.cornell],
  ),
  ('Grid', [PaperStyle.gridSmall, PaperStyle.gridLarge, PaperStyle.isometric]),
  ('Music', [PaperStyle.music]),
];

/// Every template as a live miniature (in the chosen colour, size and
/// orientation), grouped under small headings.
class TemplateGallery extends StatelessWidget {
  const TemplateGallery({
    super.key,
    required this.selected,
    required this.onSelect,
    this.tileWidth = 84,
  });

  final PageTemplate selected;
  final ValueChanged<PageTemplate> onSelect;

  /// Width of a portrait miniature; landscape tiles are wider.
  final double tileWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final landscape = selected.orientation == PageOrientation.landscape;
    final width = landscape ? tileWidth * 1.3 : tileWidth;
    // Groups flow side by side when there is room, one under the other
    // on narrow screens.
    return LayoutBuilder(
      builder: (context, constraints) => Wrap(
        spacing: Gaps.xl,
        runSpacing: Gaps.md,
        children: [
          for (final (group, styles) in templateGroups)
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: Gaps.xs, left: Gaps.xs),
                    child: Text(
                      group.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: Gaps.xxs,
                    runSpacing: Gaps.xs,
                    children: [
                      for (final style in styles)
                        TemplateTile(
                          key: ValueKey('template-${style.name}'),
                          template: selected.copyWith(style: style),
                          width: width,
                          selected: selected.style == style,
                          onTap: () => onSelect(selected.copyWith(style: style)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One selectable template miniature with its name; a check badge marks
/// the selection.
class TemplateTile extends StatelessWidget {
  const TemplateTile({
    super.key,
    required this.template,
    required this.width,
    required this.selected,
    required this.onTap,
  });

  final PageTemplate template;
  final double width;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: template.style.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.control),
        child: Padding(
          padding: const EdgeInsets.all(Gaps.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: Motion.fast,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Radii.sm),
                      border: Border.all(
                        color: selected ? scheme.primary : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(Radii.xs - 2),
                        border: Border.all(color: scheme.outlineVariant),
                        boxShadow: Shadows.low(theme.brightness),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(Radii.xs - 2),
                        child: TemplatePreview(template: template, width: width),
                      ),
                    ),
                  ),
                  if (selected)
                    Positioned(right: -2, top: -2, child: _CheckBadge(color: scheme.primary)),
                ],
              ),
              const SizedBox(height: Gaps.xs),
              SizedBox(
                width: width + 10,
                child: Text(
                  template.style.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckBadge extends StatelessWidget {
  const _CheckBadge({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).colorScheme.surface, width: 2),
      ),
      child: Icon(Icons.check_rounded, size: 12, color: Theme.of(context).colorScheme.onPrimary),
    );
  }
}
