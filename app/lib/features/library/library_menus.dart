import 'package:flutter/material.dart';

import '../../domain/notebook.dart';
import '../../ui/app_theme.dart';

/// Actions offered on a notebook (card menu, context menu).
enum NotebookAction {
  open,
  rename,
  favorite,
  duplicate,
  move,
  cover,
  trash,
  restore,
  deleteForever,
}

/// Actions offered on a folder.
enum FolderAction { open, edit, move, delete }

/// Menu items for [notebook]; trashed notebooks only restore or delete.
List<PopupMenuEntry<NotebookAction>> notebookMenuItems(Notebook notebook) {
  if (notebook.isTrashed) {
    return const [
      MenuRow(value: NotebookAction.restore, icon: Icons.restore_rounded, label: 'Restore'),
      PopupMenuDivider(),
      MenuRow(
        value: NotebookAction.deleteForever,
        icon: Icons.delete_forever_outlined,
        label: 'Delete forever',
        destructive: true,
      ),
    ];
  }
  return [
    const MenuRow(value: NotebookAction.open, icon: Icons.open_in_new_rounded, label: 'Open'),
    const MenuRow(value: NotebookAction.rename, icon: Icons.edit_outlined, label: 'Rename'),
    MenuRow(
      value: NotebookAction.favorite,
      icon: notebook.favorite ? Icons.star_rounded : Icons.star_outline_rounded,
      label: notebook.favorite ? 'Remove from favourites' : 'Add to favourites',
    ),
    const MenuRow(value: NotebookAction.cover, icon: Icons.palette_outlined, label: 'Change cover'),
    const MenuRow(
      value: NotebookAction.duplicate,
      icon: Icons.copy_all_outlined,
      label: 'Duplicate',
    ),
    const MenuRow(
      value: NotebookAction.move,
      icon: Icons.drive_file_move_outline,
      label: 'Move to folder…',
    ),
    const PopupMenuDivider(),
    const MenuRow(
      value: NotebookAction.trash,
      icon: Icons.delete_outline_rounded,
      label: 'Move to Trash',
      destructive: true,
    ),
  ];
}

const List<PopupMenuEntry<FolderAction>> folderMenuItems = [
  MenuRow(value: FolderAction.open, icon: Icons.folder_open_outlined, label: 'Open'),
  MenuRow(value: FolderAction.edit, icon: Icons.edit_outlined, label: 'Rename & colour'),
  MenuRow(value: FolderAction.move, icon: Icons.drive_file_move_outline, label: 'Move to folder…'),
  PopupMenuDivider(),
  MenuRow(
    value: FolderAction.delete,
    icon: Icons.delete_outline_rounded,
    label: 'Delete folder',
    destructive: true,
  ),
];

/// A compact menu row: icon + label, red when [destructive].
class MenuRow<T> extends PopupMenuItem<T> {
  const MenuRow({
    super.key,
    required T super.value,
    required this.icon,
    required this.label,
    this.destructive = false,
  }) : super(child: null, height: 44);

  final IconData icon;
  final String label;
  final bool destructive;

  @override
  PopupMenuItemState<T, MenuRow<T>> createState() => _MenuRowState<T>();
}

class _MenuRowState<T> extends PopupMenuItemState<T, MenuRow<T>> {
  @override
  Widget buildChild() {
    final scheme = Theme.of(context).colorScheme;
    final color = widget.destructive ? scheme.error : scheme.onSurface;
    return Row(
      children: [
        Icon(widget.icon, size: 20, color: widget.destructive ? color : scheme.onSurfaceVariant),
        const SizedBox(width: Gaps.md),
        Flexible(
          child: Text(
            widget.label,
            style: TextStyle(color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Shows a context menu at the global position [at] (or centred on the
/// widget of [context]) and returns the chosen value.
Future<T?> showContextMenuAt<T>(
  BuildContext context, {
  required List<PopupMenuEntry<T>> items,
  Offset? at,
}) {
  final box = context.findRenderObject()! as RenderBox;
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final origin = overlay.globalToLocal(at ?? box.localToGlobal(box.size.center(Offset.zero)));
  return showMenu<T>(
    context: context,
    position: RelativeRect.fromRect(origin & Size.zero, Offset.zero & overlay.size),
    items: items,
  );
}
