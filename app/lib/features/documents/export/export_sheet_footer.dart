import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_theme.dart';

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
    this.print = false,
  });

  /// Print instead of Export.
  final bool print;

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
      key: ValueKey(print ? 'print-button' : 'export-button'),
      onPressed: onExport,
      icon: Icon(print ? Symbols.print_sharp : Symbols.ios_share_sharp, size: Glyphs.bar),
      label: Text(
        print
            ? 'Print'
            : offersSaveToDevice
            ? 'Share'
            : 'Export',
      ),
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
