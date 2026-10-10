import 'package:flutter/material.dart';

import '../../domain/paper.dart';
import '../../ui/app_theme.dart';
import 'template_picker.dart';
import 'template_preview.dart';

/// A form row showing the chosen template; tapping opens the picker.
class TemplateField extends StatelessWidget {
  const TemplateField({
    super.key,
    required this.template,
    required this.onChanged,
    this.sizeEditable = true,
  });

  final PageTemplate template;
  final ValueChanged<PageTemplate> onChanged;

  /// False for infinite canvases, which have no page size.
  final bool sizeEditable;

  Future<void> _pick(BuildContext context) async {
    final choice = await showTemplatePicker(
      context,
      initial: template,
      mode: sizeEditable ? TemplatePickerMode.create : TemplatePickerMode.canvas,
    );
    if (choice != null) onChanged(choice.template);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = [
      template.color.label,
      if (sizeEditable) '${template.format.label} ${template.orientation.name}',
    ].join(' · ');
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(Radii.control),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.control),
        onTap: () => _pick(context),
        child: Padding(
          padding: const EdgeInsets.all(Gaps.sm),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: TemplatePreview(
                  template: sizeEditable ? template : template.copyWith(format: PageFormat.square),
                  width: 44,
                ),
              ),
              const SizedBox(width: Gaps.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(template.style.label, style: theme.textTheme.titleSmall),
                    Text(details, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
