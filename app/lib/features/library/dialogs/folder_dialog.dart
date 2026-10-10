import 'package:flutter/material.dart';

import '../../../ui/app_dialogs.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/color_dot.dart';

/// Name and colour of a folder, as entered in [showFolderDialog].
typedef FolderDetails = ({String name, int color});

/// Creates or edits a folder's name and colour.
Future<FolderDetails?> showFolderDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String initialName = '',
  int? initialColor,
}) {
  return showDialog<FolderDetails>(
    context: context,
    builder: (_) => _FolderDialog(
      title: title,
      confirmLabel: confirmLabel,
      initialName: initialName,
      initialColor: initialColor ?? Palette.covers.first,
    ),
  );
}

class _FolderDialog extends StatefulWidget {
  const _FolderDialog({
    required this.title,
    required this.confirmLabel,
    required this.initialName,
    required this.initialColor,
  });

  final String title;
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
    final theme = Theme.of(context);
    final color = Color(_color);
    return AlertDialog(
      // The folder as it will look, in its colour.
      icon: Center(
        child: AnimatedContainer(
          duration: Motion.medium,
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: color.withValues(alpha: theme.brightness == Brightness.dark ? 0.22 : 0.14),
            borderRadius: BorderRadius.circular(Radii.control + 4),
          ),
          child: Icon(Icons.folder_rounded, color: color, size: 36),
        ),
      ),
      title: Text(widget.title),
      content: DialogBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Name', hintText: 'Untitled folder'),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: Gaps.xl),
            Text('Colour', style: theme.textTheme.titleSmall),
            const SizedBox(height: Gaps.sm),
            // Two even rows of seven at the standard dialog width.
            Wrap(
              spacing: Gaps.lg,
              runSpacing: Gaps.sm,
              children: [
                for (var i = 0; i < Palette.covers.length; i++)
                  ColorDot(
                    color: Palette.covers[i],
                    size: 40,
                    tooltip: Palette.coverNames[i],
                    selected: Palette.covers[i] == _color,
                    onTap: () => setState(() => _color = Palette.covers[i]),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
