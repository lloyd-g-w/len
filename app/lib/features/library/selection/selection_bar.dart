import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/selection_bar.dart';
import '../library_actions.dart';
import '../library_controller.dart';
import 'library_selection.dart';
import 'selection_actions.dart';

/// The library's selection mode in the shared [SelectionBar]: done, count,
/// select all, and the batch actions (favourite, move, export, trash; or
/// restore and delete in the trash).
class LibrarySelectionBar extends StatelessWidget {
  const LibrarySelectionBar({super.key, required this.actions, required this.selection});

  final LibraryActions actions;
  final LibrarySelection selection;

  @override
  Widget build(BuildContext context) {
    final c = actions.controller;
    final visible = [for (final n in c.visibleNotebooks) n.id];
    final count = selection.count;
    final all = count == visible.length && count > 0;
    final some = count > 0;
    final trash = c.section == LibrarySection.trash;
    final allStarred =
        some && c.visibleNotebooks.where((n) => selection.contains(n.id)).every((n) => n.favorite);
    return SelectionBar(
      title: count == 0 ? 'Select notebooks' : '$count selected',
      onDone: selection.clear,
      allSelected: all,
      onSelectAll: () => all ? selection.selectAll(const []) : selection.selectAll(visible),
      enabled: some,
      commands: [
        if (trash) ...[
          SelectionCommand(
            icon: Symbols.restore_sharp,
            label: 'Restore',
            onPressed: () => actions.restoreSelected(context, selection),
          ),
          SelectionCommand(
            icon: Symbols.delete_forever_sharp,
            label: 'Delete',
            tooltip: 'Delete forever',
            destructive: true,
            onPressed: () => unawaited(actions.deleteSelectedForever(context, selection)),
          ),
        ] else ...[
          SelectionCommand(
            icon: Symbols.star_sharp,
            label: allStarred ? 'Unfavourite' : 'Favourite',
            tooltip: allStarred ? 'Remove from favourites' : 'Add to favourites',
            filled: allStarred,
            onPressed: () => actions.favoriteSelected(context, selection),
          ),
          SelectionCommand(
            icon: Symbols.drive_file_move_sharp,
            label: 'Move to folder…',
            onPressed: () => unawaited(actions.moveSelected(context, selection)),
          ),
          SelectionCommand(
            icon: Symbols.ios_share_sharp,
            label: 'Export…',
            onPressed: () => unawaited(actions.exportSelected(context, selection)),
          ),
          SelectionCommand(
            icon: Symbols.delete_sharp,
            label: 'Trash',
            tooltip: 'Move to trash',
            destructive: true,
            onPressed: () => actions.trashSelected(context, selection),
          ),
        ],
      ],
    );
  }
}
