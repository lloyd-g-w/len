import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/paper.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/roving_focus.dart';
import '../../../ui/section_label.dart';
import 'even_choices.dart';
import 'template_catalog.dart';

/// A small section heading inside pickers ("Paper", "Page size"): a
/// [SectionLabel], like the gallery's category headings, with an optional
/// caption after it ("41 pages").
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
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SectionLabel(text),
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
          RovingSegments(
            SegmentedButton<PageOrientation>(
              showSelectedIcon: false,
              expandedInsets: EdgeInsets.zero,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(
                  value: PageOrientation.portrait,
                  icon: Icon(Symbols.crop_portrait_sharp),
                  label: Text('Portrait'),
                ),
                ButtonSegment(
                  value: PageOrientation.landscape,
                  icon: Icon(Symbols.crop_landscape_sharp),
                  label: Text('Landscape'),
                ),
              ],
              selected: {template.orientation},
              onSelectionChanged: (s) => onChanged(template.copyWith(orientation: s.single)),
            ),
          ),
        ],
      ],
    );
  }
}

/// "College ruled, white, A4 portrait" (or "…, infinite canvas"): commas,
/// not a `·` chain (DESIGN §2).
String describeTemplate(PageTemplate t, {bool canvas = false}) {
  final size = canvas
      ? 'infinite canvas'
      : t.customSize != null
      ? 'template size'
      : t.format == PageFormat.square
      ? 'square'
      : '${t.format.label} ${t.orientation.name}';
  return '${t.paper.label}, ${t.color.label.toLowerCase()}, $size';
}

/// [describeTemplate] with how many pages it makes: "Daily planner,
/// white, A4 portrait, 31 pages".
String describeWithPages(PageTemplate t, int pages) =>
    '${describeTemplate(t)}, $pages ${pages == 1 ? 'page' : 'pages'}';

/// [describeTemplate] for a chooser's selection; generated planners say
/// how many pages they make ([describeWithPages]).
String describeSelection(TemplateSelection s, {bool canvas = false, bool generate = true}) {
  if (!generate || !s.style.isPlanner) return describeTemplate(s.template, canvas: canvas);
  final t = s.template.copyWith(paper: Paper(s.style));
  final pages = s.pagesToCreate().length;
  return describeWithPages(t, pages);
}
