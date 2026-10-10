import 'package:flutter/material.dart';

import '../../../domain/cover_style.dart';
import '../../../domain/notebook.dart';
import '../../../ui/app_theme.dart';
import '../cover_picker.dart';
import '../notebook_cover.dart';

/// A chosen cover.
typedef CoverChoice = ({int color, CoverStyle style});

/// Bottom sheet to restyle a notebook's cover: live preview, colours and
/// patterns, Cancel / Apply.
Future<CoverChoice?> showCoverSheet(BuildContext context, Notebook notebook) {
  return showModalBottomSheet<CoverChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 720),
    builder: (context) => _CoverSheet(notebook: notebook),
  );
}

class _CoverSheet extends StatefulWidget {
  const _CoverSheet({required this.notebook});

  final Notebook notebook;

  @override
  State<_CoverSheet> createState() => _CoverSheetState();
}

class _CoverSheetState extends State<_CoverSheet> {
  late int _color = widget.notebook.coverColor;
  late CoverStyle _style = widget.notebook.coverStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).width < 560;
    final preview = Container(
      width: compact ? 96 : 128,
      height: compact ? 132 : 176,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.cover),
        boxShadow: Shadows.high(theme.brightness),
      ),
      child: NotebookCover(color: _color, style: _style, kind: widget.notebook.kind),
    );
    final picker = CoverPicker(
      color: _color,
      style: _style,
      kind: widget.notebook.kind,
      onColor: (c) => setState(() => _color = c),
      onStyle: (s) => setState(() => _style = s),
    );
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        Gaps.xl,
        0,
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
                onPressed: () =>
                    Navigator.pop<CoverChoice>(context, (color: _color, style: _style)),
                child: const Text('Apply'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
