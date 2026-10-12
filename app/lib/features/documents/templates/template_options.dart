import 'package:flutter/material.dart';

import '../../../domain/paper.dart';
import '../../../ui/app_theme.dart';
import '../template_preview.dart';
import 'page_setup.dart';
import 'planner_options.dart';
import 'template_catalog.dart';

/// The options of a [TemplateSelection] below or beside the gallery:
/// planner dates (planners only), paper colour and page size. With
/// [preview], a larger miniature of the selection comes first (the
/// side-by-side layout, where the gallery's own tiles are further away).
class TemplateOptions extends StatelessWidget {
  const TemplateOptions({
    super.key,
    required this.selection,
    required this.onChanged,
    this.canvas = false,
    this.sizeEditable = true,
    this.generate = true,
    this.preview = false,
    this.plannerKey,
  });

  final TemplateSelection selection;
  final ValueChanged<TemplateSelection> onChanged;

  /// Choosing a canvas background: no planners, no size.
  final bool canvas;

  /// Whether page size and orientation can be chosen.
  final bool sizeEditable;

  /// Whether planners generate a range of pages (else one date).
  final bool generate;

  /// Show a preview of the selected template at the top.
  final bool preview;

  /// Key of the planner options, so they can be scrolled into view.
  final Key? plannerKey;

  /// Width of the [preview] miniature (portrait).
  static const double previewWidth = 112;

  @override
  Widget build(BuildContext context) {
    final s = selection;
    final custom = s.template.customSize != null;
    final template = canvas
        ? s.template.copyWith(orientation: PageOrientation.portrait)
        : s.template;
    void setTemplate(PageTemplate t) => onChanged(s.copyWith(template: t));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (preview) ...[
          Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.xs),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                boxShadow: Shadows.low(Theme.of(context).brightness),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Radii.xs),
                child: TemplatePreview(
                  template: template,
                  width: template.orientation == PageOrientation.landscape
                      ? previewWidth * 1.4
                      : previewWidth,
                ),
              ),
            ),
          ),
          const SizedBox(height: Gaps.lg),
        ],
        AnimatedSize(
          duration: Motion.medium,
          curve: Motion.standard,
          alignment: Alignment.topCenter,
          child: s.style.isPlanner && !canvas
              ? Padding(
                  key: plannerKey,
                  padding: EdgeInsets.only(top: preview ? 0 : Gaps.lg, bottom: Gaps.lg),
                  child: PlannerOptions(selection: s, generate: generate, onChanged: onChanged),
                )
              : SizedBox(width: double.infinity, height: preview ? 0 : Gaps.lg),
        ),
        PickerLabel(canvas ? 'Background colour' : 'Paper colour'),
        PaperColorRow(template: s.template, onChanged: setTemplate),
        if (sizeEditable && !canvas) ...[
          const SizedBox(height: Gaps.lg),
          PickerLabel('Page size', trailing: custom ? 'Set by the template' : null),
          IgnorePointer(
            ignoring: custom,
            child: Opacity(
              opacity: custom ? 0.45 : 1,
              child: PageSizeRow(template: s.template, onChanged: setTemplate),
            ),
          ),
        ],
      ],
    );
  }
}
