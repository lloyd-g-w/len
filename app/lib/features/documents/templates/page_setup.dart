import 'package:flutter/material.dart';

import '../../../domain/paper.dart';
import '../../../ui/app_theme.dart';
import 'template_catalog.dart';

/// A small section heading inside pickers ("Paper colour", "Page size").
class PickerLabel extends StatelessWidget {
  const PickerLabel(this.text, {super.key, this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Gaps.sm),
      child: Row(
        children: [
          Text(text, style: theme.textTheme.titleSmall),
          if (trailing != null) ...[
            const SizedBox(width: Gaps.sm),
            Flexible(
              child: Text(
                trailing!,
                style: theme.textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Paper colours as labelled chips with a swatch.
class PaperColorRow extends StatelessWidget {
  const PaperColorRow({super.key, required this.template, required this.onChanged});

  final PageTemplate template;
  final ValueChanged<PageTemplate> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: Gaps.sm,
      runSpacing: Gaps.sm,
      children: [
        for (final c in PaperColor.values)
          ChoiceChip(
            key: ValueKey('paper-${c.name}'),
            tooltip: c.label,
            showCheckmark: false,
            avatar: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: c.paper,
                shape: BoxShape.circle,
                border: Border.all(color: scheme.outline.withValues(alpha: 0.5)),
              ),
            ),
            label: Text(c.label),
            selected: template.color == c,
            onSelected: (_) => onChanged(template.copyWith(color: c)),
          ),
      ],
    );
  }
}

/// Page format chips plus a portrait / landscape toggle.
class PageSizeRow extends StatelessWidget {
  const PageSizeRow({super.key, required this.template, required this.onChanged});

  final PageTemplate template;
  final ValueChanged<PageTemplate> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Gaps.md,
      runSpacing: Gaps.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Wrap(
          spacing: Gaps.sm,
          runSpacing: Gaps.sm,
          children: [
            for (final f in PageFormat.values)
              ChoiceChip(
                showCheckmark: false,
                label: Text(f.label),
                selected: template.format == f,
                onSelected: (_) => onChanged(template.copyWith(format: f)),
              ),
          ],
        ),
        if (template.format != PageFormat.square)
          SegmentedButton<PageOrientation>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(
                value: PageOrientation.portrait,
                icon: Icon(Icons.crop_portrait_rounded),
                tooltip: 'Portrait',
              ),
              ButtonSegment(
                value: PageOrientation.landscape,
                icon: Icon(Icons.crop_landscape_rounded),
                tooltip: 'Landscape',
              ),
            ],
            selected: {template.orientation},
            onSelectionChanged: (s) => onChanged(template.copyWith(orientation: s.single)),
          ),
      ],
    );
  }
}

/// "College ruled · White · A4 portrait" (or "… · Infinite canvas").
String describeTemplate(PageTemplate t, {bool canvas = false}) {
  final size = canvas
      ? 'Infinite canvas'
      : t.customSize != null
      ? 'Template size'
      : t.format == PageFormat.square
      ? 'Square'
      : '${t.format.label} ${t.orientation.name}';
  return '${t.paper.label} · ${t.color.label} · $size';
}

/// [describeTemplate] for a chooser's selection; generated planners say
/// how many pages they make ("Daily planner · White · A4 portrait · 31
/// pages").
String describeSelection(TemplateSelection s, {bool canvas = false, bool generate = true}) {
  if (!generate || !s.style.isPlanner) return describeTemplate(s.template, canvas: canvas);
  final t = s.template.copyWith(paper: Paper(s.style));
  final pages = s.pagesToCreate().length;
  return '${describeTemplate(t)} · $pages ${pages == 1 ? 'page' : 'pages'}';
}
