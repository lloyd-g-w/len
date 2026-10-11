import 'package:flutter/material.dart';

import '../../../ui/app_theme.dart';
import '../../documents/templates/page_setup.dart';
import '../../documents/templates/template_catalog.dart';
import '../../documents/templates/template_chooser.dart';

/// Template gallery, planner dates, paper colour and (for notebooks) page
/// size.
class PaperTab extends StatelessWidget {
  const PaperTab({
    super.key,
    required this.selection,
    required this.canvas,
    required this.tileWidth,
    required this.onChanged,
  });

  final TemplateSelection selection;
  final bool canvas;
  final double tileWidth;
  final ValueChanged<TemplateSelection> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          describeSelection(selection, canvas: canvas),
          key: const ValueKey('template-summary'),
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: Gaps.lg),
        TemplateChooser(
          selection: selection,
          canvas: canvas,
          tileWidth: tileWidth,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
