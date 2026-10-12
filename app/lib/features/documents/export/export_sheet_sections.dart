import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_theme.dart';
import 'export_options.dart';

/// A titled group of the export sheet: a small label above a rounded card.
class ExportSection extends StatelessWidget {
  const ExportSection({super.key, required this.title, required this.children, this.trailing});

  final String title;

  /// Shown at the end of the title row (e.g. "12 pages").
  final String? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Gaps.xs, 0, Gaps.xs, Gaps.sm),
          child: Row(
            children: [
              Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
              if (trailing != null) Text(trailing!, style: muted),
            ],
          ),
        ),
        Material(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(Radii.sm),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Gaps.xs),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      ],
    );
  }
}

/// PDF / PNG choice with a line on what each produces.
class ExportFormatPicker extends StatelessWidget {
  const ExportFormatPicker({super.key, required this.format, required this.onChanged});

  final ExportFormat format;
  final ValueChanged<ExportFormat> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<ExportFormat>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: ExportFormat.pdf,
              icon: Icon(Symbols.picture_as_pdf_rounded),
              label: Text('PDF'),
            ),
            ButtonSegment(
              value: ExportFormat.png,
              icon: Icon(Symbols.image_rounded),
              label: Text('PNG'),
            ),
          ],
          selected: {format},
          onSelectionChanged: (s) => onChanged(s.single),
        ),
        const SizedBox(height: Gaps.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gaps.xs),
          child: Text(
            format == ExportFormat.pdf
                ? 'One document with sharp, zoomable ink.'
                : 'One image per page, for slides and messages.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
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
          _option(ExportRange.all, 'All pages', '$pageCount pages'),
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
  );

  Widget _rangeField() => Padding(
    padding: const EdgeInsets.fromLTRB(Gaps.lg, Gaps.xs, Gaps.lg, Gaps.md),
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
        prefixIcon: const Icon(Symbols.format_list_numbered_rounded),
      ),
    ),
  );
}

/// The pinned bottom of the export sheet: what will be exported, Cancel
/// and Export. Stacks the summary above the buttons when narrow.
class ExportSheetFooter extends StatelessWidget {
  const ExportSheetFooter({
    super.key,
    required this.summary,
    required this.onExport,
    this.bottomInset = 0,
  });

  final String summary;

  /// Null while the choice is invalid.
  final VoidCallback? onExport;

  /// Extra bottom padding (system navigation bar).
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = Text(
      summary,
      key: const ValueKey('export-summary'),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
    );
    final cancel = TextButton(
      onPressed: () => Navigator.of(context).pop(),
      child: const Text('Cancel'),
    );
    final export = FilledButton.icon(
      key: const ValueKey('export-button'),
      onPressed: onExport,
      icon: const Icon(Symbols.ios_share_rounded, size: 20),
      label: const Text('Export'),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(Gaps.xl, Gaps.md, Gaps.xl, Gaps.md + bottomInset),
        child: LayoutBuilder(
          builder: (context, c) => c.maxWidth < 300
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    text,
                    const SizedBox(height: Gaps.sm),
                    Row(
                      children: [
                        Expanded(child: cancel),
                        const SizedBox(width: Gaps.sm),
                        Expanded(child: export),
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: text),
                    const SizedBox(width: Gaps.md),
                    cancel,
                    const SizedBox(width: Gaps.sm),
                    export,
                  ],
                ),
        ),
      ),
    );
  }
}
