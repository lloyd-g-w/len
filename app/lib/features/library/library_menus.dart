import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../domain/notebook.dart';
import '../../ui/app_theme.dart';
import '../../ui/menus.dart';
import '../../ui/section_label.dart';

export '../../ui/menus.dart';

/// Actions offered on a notebook (card menu, context menu).
enum NotebookAction {
  open,
  rename,
  favorite,
  duplicate,
  move,
  cover,
  export,
  select,
  trash,
  restore,
  deleteForever,
}

/// Actions offered on a folder.
enum FolderAction { open, edit, move, export, delete }

/// Menu items for [notebook]; trashed notebooks only restore or delete.
List<PopupMenuEntry<NotebookAction>> notebookMenuItems(Notebook notebook) {
  if (notebook.isTrashed) {
    return const [
      MenuRow(value: NotebookAction.restore, icon: Symbols.restore_sharp, label: 'Restore'),
      PopupMenuDivider(),
      MenuRow(
        value: NotebookAction.deleteForever,
        icon: Symbols.delete_forever_sharp,
        label: 'Delete forever…',
        destructive: true,
      ),
    ];
  }
  return [
    const MenuRow(value: NotebookAction.open, icon: Symbols.open_in_new_sharp, label: 'Open'),
    const MenuRow(value: NotebookAction.rename, icon: Symbols.edit_sharp, label: 'Rename…'),
    MenuRow(
      value: NotebookAction.favorite,
      icon: Symbols.star_sharp,
      filledIcon: notebook.favorite,
      label: notebook.favorite ? 'Remove from favourites' : 'Add to favourites',
    ),
    const MenuRow(value: NotebookAction.cover, icon: Symbols.palette_sharp, label: 'Change cover…'),
    const MenuRow(
      value: NotebookAction.duplicate,
      icon: Symbols.library_add_sharp,
      label: 'Duplicate',
    ),
    const MenuRow(
      value: NotebookAction.move,
      icon: Symbols.drive_file_move_sharp,
      label: 'Move to folder…',
    ),
    const MenuRow(value: NotebookAction.export, icon: Symbols.ios_share_sharp, label: 'Export…'),
    const MenuRow(value: NotebookAction.select, icon: Symbols.check_circle_sharp, label: 'Select'),
    const PopupMenuDivider(),
    const MenuRow(
      value: NotebookAction.trash,
      icon: Symbols.delete_sharp,
      label: 'Move to trash',
      destructive: true,
    ),
  ];
}

const List<PopupMenuEntry<FolderAction>> folderMenuItems = [
  MenuRow(value: FolderAction.open, icon: Symbols.folder_open_sharp, label: 'Open'),
  MenuRow(value: FolderAction.edit, icon: Symbols.edit_sharp, label: 'Edit folder…'),
  MenuRow(value: FolderAction.move, icon: Symbols.drive_file_move_sharp, label: 'Move to folder…'),
  MenuRow(value: FolderAction.export, icon: Symbols.ios_share_sharp, label: 'Export…'),
  PopupMenuDivider(),
  MenuRow(
    value: FolderAction.delete,
    icon: Symbols.delete_sharp,
    label: 'Delete folder',
    destructive: true,
  ),
];

/// A group heading in a popup menu ("Sort by"): a [SectionLabel] lined up
/// with the rows' icons.
class MenuHeading<T> extends PopupMenuEntry<T> {
  const MenuHeading(this.text, {super.key});

  final String text;

  @override
  double get height => 32;

  @override
  bool represents(T? value) => false;

  @override
  State<MenuHeading<T>> createState() => _MenuHeadingState<T>();
}

class _MenuHeadingState<T> extends State<MenuHeading<T>> {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Gaps.md, Gaps.sm, Gaps.md, Gaps.xxs),
    child: SectionLabel(widget.text),
  );
}
