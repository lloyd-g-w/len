import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_theme.dart';
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
              icon: Icon(Symbols.picture_as_pdf_sharp),
              label: Text('PDF'),
            ),
            ButtonSegment(
              value: ExportFormat.png,
              icon: Icon(Symbols.image_sharp),
              label: Text('PNG'),
            ),
          ],
          selected: {format},
          onSelectionChanged: (s) => onChanged(s.single),
        ),
        const SizedBox(height: Gaps.sm),
        Text(
          format == ExportFormat.pdf
              ? 'One document with sharp, zoomable ink'
              : 'One image per page, for slides and messages',
          style: theme.textTheme.bodySmall,
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

/// The pinned bottom of the export sheet: what will be exported, Cancel
/// and Export. Stacks the summary above the buttons when narrow.
class ExportSheetFooter extends StatelessWidget {
  const ExportSheetFooter({
    super.key,
    required this.summary,
    required this.onExport,
    this.onSaveToDevice,
    this.offersSaveToDevice = false,
    this.bottomInset = 0,
  });

  /// "Save to device" (Android, beside Share); null while the choice is
  /// invalid.
  final VoidCallback? onSaveToDevice;

  /// Whether Save to device and Share are offered instead of Export.
  final bool offersSaveToDevice;

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
      icon: const Icon(Symbols.ios_share_sharp, size: Glyphs.bar),
      label: Text(offersSaveToDevice ? 'Share' : 'Export'),
    );
    // Android: both ways out, side by side under the summary (the header's
    // ✕ cancels); stacked, Share on top, when narrow or with large text.
    final saveToDevice = OutlinedButton.icon(
      key: const ValueKey('save-to-device-button'),
      onPressed: onSaveToDevice,
      icon: const Icon(Symbols.download_sharp, size: Glyphs.bar),
      label: const Text('Save to device'),
    );
    Widget pair(double width) => width / MediaQuery.textScalerOf(context).scale(1) < 340
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              export,
              const SizedBox(height: Gaps.sm),
              saveToDevice,
            ],
          )
        : Row(
            children: [
              Expanded(child: saveToDevice),
              const SizedBox(width: Gaps.sm),
              Expanded(child: export),
            ],
          );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(Gaps.xl, Gaps.md, Gaps.xl, Gaps.md + bottomInset),
        child: LayoutBuilder(
          builder: (context, c) => offersSaveToDevice
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    text,
                    const SizedBox(height: Gaps.sm),
                    pair(c.maxWidth),
                  ],
                )
              : c.maxWidth < 300
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
