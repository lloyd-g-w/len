import 'package:flutter/material.dart';

import '../../../domain/notebook.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/dialog_or_sheet.dart';
import '../../../ui/messages.dart';
import '../../../ui/sheet_parts.dart';
import '../../documents/templates/page_setup.dart' show PickerLabel;
import '../library_controller.dart';
import '../new_notebook/cover_row.dart';
import '../notebook_cover.dart';

/// Recolours [notebook]'s cover: a live preview and the colours, each
/// applied on tap (no Apply; a dialog on wide screens, a bottom sheet on
/// phones, both closed with their ✕). Once it closes on a new colour,
/// "Cover changed" offers Undo.
Future<void> changeCover(
  BuildContext context,
  LibraryController controller,
  Notebook notebook,
) async {
  void apply(int color) {
    // Re-read: it may have changed (or gone) while the sheet was open.
    final current = controller.services.notebooks.get(notebook.id);
    if (current != null && current.coverColor != color) {
      controller.updateNotebook(current.copyWith(coverColor: color));
    }
  }

  final before = notebook.coverColor;
  var after = before;
  await showDialogOrSheet<void>(
    context: context,
    maxWidth: 640,
    builder: (context, wide) =>
        _CoverSheet(notebook: notebook, wide: wide, onColor: (c) => apply(after = c)),
  );
  if (after == before || !context.mounted) return;
  showMessage(
    context,
    'Cover changed',
    action: SnackBarAction(label: 'Undo', onPressed: () => apply(before)),
  );
}

class _CoverSheet extends StatefulWidget {
  const _CoverSheet({required this.notebook, required this.wide, required this.onColor});

  final Notebook notebook;
  final ValueChanged<int> onColor;

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
    final picker = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PickerLabel('Colour', trailing: Palette.coverName(_color)),
        CoverRow(
          color: _color,
          onColor: (c) {
            setState(() => _color = c);
            widget.onColor(c);
          },
        ),
      ],
    );
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
          SheetHeader(
            title: 'Cover',
            subtitle: widget.notebook.title,
            onClose: () => Navigator.of(context).pop(),
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
        ],
      ),
    );
  }
}
