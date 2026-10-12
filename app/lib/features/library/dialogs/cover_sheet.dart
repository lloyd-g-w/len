import 'package:flutter/material.dart';

import '../../../domain/notebook.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/dialog_or_sheet.dart';
import '../cover_picker.dart';
import '../notebook_cover.dart';

/// Recolours a notebook's cover: live preview, colours,
/// Cancel / Apply. A dialog on wide screens, a bottom sheet on phones.
/// Returns the chosen ARGB colour.
Future<int?> showCoverSheet(BuildContext context, Notebook notebook) {
  return showDialogOrSheet<int>(
    context: context,
    maxWidth: 640,
    builder: (context, wide) => _CoverSheet(notebook: notebook, wide: wide),
  );
}

class _CoverSheet extends StatefulWidget {
  const _CoverSheet({required this.notebook, required this.wide});

  final Notebook notebook;

  /// In a dialog (no drag handle above).
  final bool wide;

  @override
  State<_CoverSheet> createState() => _CoverSheetState();
}

class _CoverSheetState extends State<_CoverSheet> {
  late int _color = widget.notebook.coverColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).width < 560;
    final preview = Container(
      width: compact ? 96 : 128,
      height: compact ? 132 : 176,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.sm),
        boxShadow: Shadows.high(theme.brightness),
      ),
      child: NotebookCover(color: _color, kind: widget.notebook.kind),
    );
    final picker = CoverPicker(color: _color, onColor: (c) => setState(() => _color = c));
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        Gaps.xl,
        widget.wide ? Gaps.xl : 0,
        Gaps.xl,
        Gaps.lg + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Cover', style: theme.textTheme.headlineSmall),
          Text(
            widget.notebook.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: Gaps.xl),
          if (compact) ...[
            Center(child: preview),
            const SizedBox(height: Gaps.xl),
            picker,
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                preview,
                const SizedBox(width: Gaps.xxl),
                Expanded(child: picker),
              ],
            ),
          const SizedBox(height: Gaps.xl),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              const SizedBox(width: Gaps.sm),
              FilledButton(
                onPressed: () => Navigator.pop<int>(context, _color),
                child: const Text('Apply'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
