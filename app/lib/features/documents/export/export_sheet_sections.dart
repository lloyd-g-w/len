import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/roving_focus.dart';
import '../../../ui/section_label.dart';
import 'export_options.dart';

/// A titled group of the export sheet: a Small label heading over an open
/// ruled list (DESIGN §6: hairlines, not plates).
class ExportSection extends StatelessWidget {
  const ExportSection({super.key, required this.title, required this.children, this.trailing});

  final String title;

  /// Shown at the end of the title row (e.g. "12 pages").
  final String? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: Gaps.sm),
          child: Row(
            children: [
              Expanded(child: SectionLabel(title)),
              if (trailing != null) Text(trailing!, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        for (final child in children) ...[const ExportRule(), child],
      ],
    );
  }
}

/// The hairline between the rows of an [ExportSection].
class ExportRule extends StatelessWidget {
  const ExportRule({super.key});

  @override
  Widget build(BuildContext context) => Divider(
    height: Hairline.width,
    thickness: Hairline.width,
    color: Theme.of(context).colorScheme.outlineVariant,
  );
}

/// PDF / PNG / Len choice with a line on what each produces.
class ExportFormatPicker extends StatelessWidget {
  const ExportFormatPicker({super.key, required this.format, required this.onChanged});

  final ExportFormat format;
  final ValueChanged<ExportFormat> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.15;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RovingSegments(
          SegmentedButton<ExportFormat>(
            showSelectedIcon: false,
            segments: [
              for (final (value, icon) in [
                (ExportFormat.pdf, Symbols.picture_as_pdf_sharp),
                (ExportFormat.png, Symbols.image_sharp),
                (ExportFormat.len, Symbols.stylus_note_sharp),
              ])
                ButtonSegment(
                  value: value,
                  // Large text: names only, on one line ("Len file").
                  icon: large ? null : Icon(icon),
                  label: Text(value == ExportFormat.len ? 'Len file' : value.label, maxLines: 1),
                ),
            ],
            selected: {format},
            onSelectionChanged: (s) => onChanged(s.single),
          ),
        ),
        const SizedBox(height: Gaps.sm),
        Text(switch (format) {
          ExportFormat.pdf => 'One document with sharp, zoomable ink',
          ExportFormat.png => 'One image per page, for slides and messages',
          ExportFormat.len => 'An editable copy to open in Len: ink, text, PDFs, images and audio',
        }, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// Current page / all pages / a typed range, with the range's error inline.
class ExportPagesPicker extends StatelessWidget {
  const ExportPagesPicker({
    super.key,
    required this.range,
    required this.onRange,
    required this.currentPage,
    required this.pageCount,
    required this.rangeController,
    required this.rangeFocus,
    required this.onRangeText,
    this.rangeError,
  });

  final ExportRange range;
  final ValueChanged<ExportRange> onRange;

  /// Zero-based.
  final int currentPage;
  final int pageCount;
  final TextEditingController rangeController;
  final FocusNode rangeFocus;
  final ValueChanged<String> onRangeText;
  final String? rangeError;

  @override
  Widget build(BuildContext context) {
    return RadioGroup<ExportRange>(
      groupValue: range,
      onChanged: (r) {
        if (r != null) onRange(r);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _option(ExportRange.current, 'Current page', 'Page ${currentPage + 1}'),
          const ExportRule(),
          _option(ExportRange.all, 'All pages', '$pageCount pages'),
          const ExportRule(),
          _option(ExportRange.custom, 'Page range', 'Choose which pages'),
          AnimatedSize(
            duration: Motion.medium,
            curve: Motion.standard,
            alignment: Alignment.topCenter,
            child: range == ExportRange.custom ? _rangeField() : const SizedBox(width: 0),
          ),
        ],
      ),
    );
  }

  Widget _option(ExportRange value, String title, String detail) => RadioListTile<ExportRange>(
    value: value,
    title: Text(title),
    subtitle: Text(detail),
    controlAffinity: ListTileControlAffinity.trailing,
    visualDensity: VisualDensity.compact,
    contentPadding: EdgeInsets.zero,
  );

  Widget _rangeField() => Padding(
    padding: const EdgeInsets.only(top: Gaps.xs, bottom: Gaps.md),
    child: TextField(
      key: const ValueKey('export-range'),
      controller: rangeController,
      focusNode: rangeFocus,
      keyboardType: TextInputType.text,
      textInputAction: TextInputAction.done,
      onChanged: onRangeText,
      decoration: InputDecoration(
        isDense: true,
        hintText: 'e.g. 1-3, 5',
        helperText: 'Pages 1–$pageCount, separated by commas',
        errorText: rangeError,
      ),
    ),
  );
}
