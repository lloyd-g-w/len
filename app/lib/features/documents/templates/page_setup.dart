import 'package:flutter/material.dart';

import '../../../domain/paper.dart';
import '../../../ui/app_theme.dart';
import 'even_choices.dart';
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

/// Paper colours as labelled chips with a swatch, in even rows.
class PaperColorRow extends StatelessWidget {
  const PaperColorRow({super.key, required this.template, required this.onChanged});

  final PageTemplate template;
  final ValueChanged<PageTemplate> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return EvenChoices(
      choices: [
        for (final c in PaperColor.values)
          EvenChoice(
            key: ValueKey('paper-${c.name}'),
            label: c.label,
            selected: template.color == c,
            onTap: () => onChanged(template.copyWith(color: c)),
            leading: DecoratedBox(
              decoration: BoxDecoration(
                color: c.paper,
                shape: BoxShape.circle,
                border: Border.all(color: scheme.outline.withValues(alpha: 0.6)),
              ),
            ),
          ),
      ],
    );
  }
}

/// Page format chips (even rows) above a portrait / landscape toggle.
class PageSizeRow extends StatelessWidget {
  const PageSizeRow({super.key, required this.template, required this.onChanged});

  final PageTemplate template;
  final ValueChanged<PageTemplate> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EvenChoices(
          choices: [
            for (final f in PageFormat.values)
              EvenChoice(
                key: ValueKey('format-${f.name}'),
                label: f.label,
                selected: template.format == f,
                onTap: () => onChanged(template.copyWith(format: f)),
              ),
          ],
        ),
        if (template.format != PageFormat.square) ...[
          const SizedBox(height: Gaps.sm),
          SegmentedButton<PageOrientation>(
            showSelectedIcon: false,
            expandedInsets: EdgeInsets.zero,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(
                value: PageOrientation.portrait,
                icon: Icon(Icons.crop_portrait_rounded),
                label: Text('Portrait'),
              ),
              ButtonSegment(
                value: PageOrientation.landscape,
                icon: Icon(Icons.crop_landscape_rounded),
                label: Text('Landscape'),
              ),
            ],
            selected: {template.orientation},
            onSelectionChanged: (s) => onChanged(template.copyWith(orientation: s.single)),
          ),
        ],
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
