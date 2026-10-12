import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../domain/notebook.dart';
import '../../ui/menus.dart';

export '../../ui/menus.dart';

/// Actions offered on a notebook (card menu, context menu).
enum NotebookAction {
  open,
  rename,
  favorite,
  duplicate,
  move,
  cover,
  select,
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
      MenuRow(value: NotebookAction.restore, icon: Symbols.restore_rounded, label: 'Restore'),
      PopupMenuDivider(),
      MenuRow(
        value: NotebookAction.deleteForever,
        icon: Symbols.delete_forever_rounded,
        label: 'Delete forever…',
        destructive: true,
      ),
    ];
  }
  return [
    const MenuRow(value: NotebookAction.open, icon: Symbols.open_in_new_rounded, label: 'Open'),
    const MenuRow(value: NotebookAction.rename, icon: Symbols.edit_rounded, label: 'Rename…'),
    MenuRow(
      value: NotebookAction.favorite,
      icon: Symbols.star_rounded,
      filledIcon: notebook.favorite,
      label: notebook.favorite ? 'Remove from favourites' : 'Add to favourites',
    ),
    const MenuRow(
      value: NotebookAction.cover,
      icon: Symbols.palette_rounded,
      label: 'Change cover…',
    ),
    const MenuRow(
      value: NotebookAction.duplicate,
      icon: Symbols.library_add_rounded,
      label: 'Duplicate',
    ),
    const MenuRow(
      value: NotebookAction.move,
      icon: Symbols.drive_file_move_rounded,
      label: 'Move to folder…',
    ),
    const MenuRow(
      value: NotebookAction.select,
      icon: Symbols.check_circle_rounded,
      label: 'Select…',
    ),
    const PopupMenuDivider(),
    const MenuRow(
      value: NotebookAction.trash,
      icon: Symbols.delete_rounded,
      label: 'Move to trash',
      destructive: true,
    ),
  ];
}

const List<PopupMenuEntry<FolderAction>> folderMenuItems = [
  MenuRow(value: FolderAction.open, icon: Symbols.folder_open_rounded, label: 'Open'),
  MenuRow(value: FolderAction.edit, icon: Symbols.edit_rounded, label: 'Edit folder…'),
  MenuRow(
    value: FolderAction.move,
    icon: Symbols.drive_file_move_rounded,
    label: 'Move to folder…',
  ),
  PopupMenuDivider(),
  MenuRow(
    value: FolderAction.delete,
    icon: Symbols.delete_rounded,
    label: 'Delete folder…',
    destructive: true,
  ),
];
