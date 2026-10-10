import 'package:flutter/material.dart';

import '../../../domain/paper.dart';
import '../../../ui/app_theme.dart';
import '../../documents/templates/page_setup.dart';
import '../../documents/templates/template_gallery.dart';

/// Template gallery, paper colour and (for notebooks) page size.
class PaperTab extends StatelessWidget {
  const PaperTab({
    super.key,
    required this.template,
    required this.canvas,
    required this.tileWidth,
    required this.onChanged,
  });

  final PageTemplate template;
  final bool canvas;
  final double tileWidth;
  final ValueChanged<PageTemplate> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          describeTemplate(template, canvas: canvas),
          key: const ValueKey('template-summary'),
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: Gaps.lg),
        TemplateGallery(
          selected: canvas ? template.copyWith(orientation: PageOrientation.portrait) : template,
          tileWidth: tileWidth,
          onSelect: (t) => onChanged(template.copyWith(style: t.style)),
        ),
        const SizedBox(height: Gaps.sm),
        PickerLabel(canvas ? 'Background colour' : 'Paper colour'),
        PaperColorRow(template: template, onChanged: onChanged),
        if (!canvas) ...[
          const SizedBox(height: Gaps.xl),
          const PickerLabel('Page size'),
          PageSizeRow(template: template, onChanged: onChanged),
        ],
      ],
    );
  }
}
