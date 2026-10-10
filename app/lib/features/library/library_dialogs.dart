import 'package:flutter/material.dart';

import '../../domain/cover_style.dart';
import '../../domain/folder.dart';
import '../../domain/notebook.dart';
import '../../ui/app_theme.dart';
import '../../ui/color_dot.dart';
import 'cover_picker.dart';
import 'library_controller.dart';
import 'notebook_cover.dart';

export '../../ui/app_dialogs.dart' show confirmAction;

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
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Folder name',
                prefixIcon: Icon(Icons.folder_rounded, color: Color(_color)),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: Gaps.lg),
            Wrap(
              spacing: Gaps.xxs,
              runSpacing: Gaps.xxs,
              children: [
                for (final c in Palette.covers)
                  ColorDot(
                    color: c,
                    selected: c == _color,
                    onTap: () => setState(() => _color = c),
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

/// The destination chosen in [showMoveDialog]; `folderId` null = root.
typedef MoveTarget = ({String? folderId});

/// Lets the user pick a destination folder. [movingFolderId] excludes that
/// folder's subtree; [currentFolderId] is shown as the current location.
Future<MoveTarget?> showMoveDialog(
  BuildContext context, {
  required LibraryController controller,
  required String title,
  String? currentFolderId,
  String? movingFolderId,
}) {
  final excluded = <String>{};
  if (movingFolderId != null) {
    void exclude(String id) {
      excluded.add(id);
      for (final c in controller.childrenOf(id)) {
        exclude(c.id);
      }
    }

    exclude(movingFolderId);
  }
  final rows = <({Folder? folder, int depth})>[(folder: null, depth: 0)];
  void addChildren(String? parent, int depth) {
    for (final f in controller.childrenOf(parent)) {
      if (excluded.contains(f.id)) continue;
      rows.add((folder: f, depth: depth));
      addChildren(f.id, depth + 1);
    }
  }

  addChildren(null, 1);
  return showDialog<MoveTarget>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        title: Text(title),
        contentPadding: const EdgeInsets.fromLTRB(Gaps.md, Gaps.lg, Gaps.md, 0),
        content: SizedBox(
          width: 380,
          height: 360,
          child: ListView(
            children: [
              for (final row in rows)
                ListTile(
                  contentPadding: EdgeInsets.only(left: Gaps.md + row.depth * 20.0, right: Gaps.md),
                  leading: Icon(
                    row.folder == null ? Icons.auto_stories_rounded : Icons.folder_rounded,
                    color: row.folder == null
                        ? theme.colorScheme.primary
                        : Color(row.folder!.color),
                  ),
                  title: Text(row.folder?.name ?? 'Library'),
                  enabled: row.folder?.id != currentFolderId,
                  trailing: row.folder?.id == currentFolderId
                      ? Text('Current', style: theme.textTheme.bodySmall)
                      : null,
                  onTap: () => Navigator.pop<MoveTarget>(context, (folderId: row.folder?.id)),
                ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
      );
    },
  );
}

/// A chosen cover.
typedef CoverChoice = ({int color, CoverStyle style});

/// Bottom sheet to restyle a notebook's cover.
Future<CoverChoice?> showCoverSheet(BuildContext context, Notebook notebook) {
  return showModalBottomSheet<CoverChoice>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      var color = notebook.coverColor;
      var style = notebook.coverStyle;
      return StatefulBuilder(
        builder: (context, setState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Gaps.xl, 0, Gaps.xl, Gaps.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cover', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: Gaps.lg),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 96,
                      height: 132,
                      child: NotebookCover(color: color, style: style, kind: notebook.kind),
                    ),
                    const SizedBox(width: Gaps.xl),
                    Expanded(
                      child: CoverPicker(
                        color: color,
                        style: style,
                        kind: notebook.kind,
                        onColor: (c) => setState(() => color = c),
                        onStyle: (s) => setState(() => style = s),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Gaps.xl),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.pop<CoverChoice>(context, (color: color, style: style)),
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
