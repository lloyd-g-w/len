import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/dialog_or_sheet.dart';
import '../../../ui/sheet_parts.dart';
import '../../documents/templates/page_setup.dart';
import '../new_notebook/cover_row.dart';

/// Name and colour of a folder, as entered in [showFolderDialog].
typedef FolderDetails = ({String name, int color});

/// Creates or edits a folder's name and colour: a task sheet (a dialog on
/// wide screens, a bottom sheet on phones).
Future<FolderDetails?> showFolderDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String initialName = '',
  int? initialColor,
}) {
  return showDialogOrSheet<FolderDetails>(
    context: context,
    maxWidth: 440,
    minHeight: 420,
    builder: (_, wide) => _FolderDialog(
      title: title,
      confirmLabel: confirmLabel,
      initialName: initialName,
      initialColor: initialColor ?? Palette.covers.first,
      wide: wide,
    ),
  );
}

class _FolderDialog extends StatefulWidget {
  const _FolderDialog({
    required this.title,
    required this.confirmLabel,
    required this.initialName,
    required this.initialColor,
    required this.wide,
  });

  final String title;

  /// In a dialog (else a sheet with a drag handle above).
  final bool wide;
  final String confirmLabel;
  final String initialName;
  final int initialColor;

  @override
  State<_FolderDialog> createState() => _FolderDialogState();
}

class _FolderDialogState extends State<_FolderDialog> {
  late final _name = TextEditingController(text: widget.initialName)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.initialName.length);
  late int _color = widget.initialColor;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    Navigator.pop<FolderDetails>(context, (
      name: name.isEmpty ? 'Untitled folder' : name,
      color: _color,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final color = Color(_color);
    final media = MediaQuery.of(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        Gaps.xl,
        widget.wide ? Gaps.lg : 0,
        Gaps.xl,
        Gaps.lg + media.viewInsets.bottom + (widget.wide ? 0 : media.padding.bottom),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(title: widget.title, onClose: () => Navigator.pop(context)),
          const SizedBox(height: Gaps.lg),
          Row(
            children: [
              // The folder as it will look, in its colour.
              AnimatedSwitcher(
                duration: Motion.fast,
                child: Icon(
                  Symbols.folder_rounded,
                  key: ValueKey(_color),
                  fill: 1,
                  color: color,
                  size: 44,
                ),
              ),
              const SizedBox(width: Gaps.md),
              Expanded(
                child: TextField(
                  controller: _name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Name', hintText: 'Untitled folder'),
                  onSubmitted: (_) => _submit(),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gaps.xl),
          PickerLabel('Colour', trailing: Palette.coverName(_color)),
          CoverRow(color: _color, onColor: (c) => setState(() => _color = c)),
          const SizedBox(height: Gaps.xl),
          SheetActions(
            stacked: !widget.wide,
            onCancel: widget.wide ? () => Navigator.pop(context) : null,
            primary: FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
          ),
        ],
      ),
    );
  }
}
