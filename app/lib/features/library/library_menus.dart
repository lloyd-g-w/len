import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../domain/notebook.dart';
import '../../ui/app_theme.dart';
import '../../ui/menus.dart';
import '../../ui/section_label.dart';

export '../../ui/menus.dart';

/// Actions offered on a notebook (card menu, context menu). Opening is a
/// tap, not a row (UX_AUDIT R9-7).
enum NotebookAction {
  rename,
  favorite,
  duplicate,
  history,
  move,
  cover,
  export,
  print,
  select,
  trash,
  restore,
  deleteForever,
}

/// Actions offered on a folder.
enum FolderAction { rename, move, export, delete }

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
      value: NotebookAction.history,
      icon: Symbols.history_rounded,
      label: 'Version history…',
    ),
    const MenuRow(
      value: NotebookAction.move,
      icon: Symbols.drive_file_move_rounded,
      label: 'Move to folder…',
    ),
    const MenuRow(value: NotebookAction.export, icon: Symbols.ios_share_rounded, label: 'Export…'),
    const MenuRow(value: NotebookAction.print, icon: Symbols.print_rounded, label: 'Print…'),
    const MenuRow(
      value: NotebookAction.select,
      icon: Symbols.check_circle_rounded,
      label: 'Select',
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
  // Like a notebook's; its dialog changes the colour too (UX_AUDIT R9-4).
  MenuRow(value: FolderAction.rename, icon: Symbols.edit_rounded, label: 'Rename…'),
  MenuRow(
    value: FolderAction.move,
    icon: Symbols.drive_file_move_rounded,
    label: 'Move to folder…',
  ),
  // A folder exports as a Len file (one name for every Export, R8-20).
  MenuRow(value: FolderAction.export, icon: Symbols.ios_share_rounded, label: 'Export…'),
  PopupMenuDivider(),
  MenuRow(
    value: FolderAction.delete,
    icon: Symbols.delete_rounded,
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
