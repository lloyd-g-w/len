import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/floating_panel.dart';
import '../../../ui/labelled_action.dart';
import '../library_actions.dart';
import '../library_controller.dart';
import 'library_selection.dart';
import 'selection_actions.dart';

/// Floating bar of the library's selection mode: done, count, select all,
/// and the batch actions (favourite, move, trash; or restore and delete in
/// the trash), each named under its glyph like the overview's, within thumb
/// reach at the bottom. Where one row doesn't fit (phones), the actions
/// take a second row under the count.
class LibrarySelectionBar extends StatelessWidget {
  const LibrarySelectionBar({super.key, required this.actions, required this.selection});

  final LibraryActions actions;
  final LibrarySelection selection;

  /// The narrowest bar that keeps everything on one row.
  static const double _oneRow = 520;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = actions.controller;
    final visible = [for (final n in c.visibleNotebooks) n.id];
    final count = selection.count;
    final all = count == visible.length && count > 0;
    final some = count > 0;
    final trash = c.section == LibrarySection.trash;
    final allStarred =
        some && c.visibleNotebooks.where((n) => selection.contains(n.id)).every((n) => n.favorite);
    Widget action(
      String label,
      String tooltip,
      IconData icon,
      VoidCallback onPressed, {
      Color? color,
      bool filled = false,
    }) => Tooltip(
      message: tooltip,
      excludeFromSemantics: label == tooltip,
      child: LabelledAction(
        icon: icon,
        label: label,
        color: color,
        filled: filled,
        onPressed: some ? onPressed : null,
      ),
    );
    final commands = [
      if (trash) ...[
        action(
          'Restore',
          'Restore',
          Symbols.restore_sharp,
          () => actions.restoreSelected(context, selection),
        ),
        action(
          'Delete',
          'Delete forever',
          Symbols.delete_forever_sharp,
          () => unawaited(actions.deleteSelectedForever(context, selection)),
          color: scheme.error,
        ),
      ] else ...[
        action(
          allStarred ? 'Unfavourite' : 'Favourite',
          allStarred ? 'Remove from favourites' : 'Add to favourites',
          Symbols.star_sharp,
          () => actions.favoriteSelected(context, selection),
          filled: allStarred,
        ),
        action(
          'Move',
          'Move to folder…',
          Symbols.drive_file_move_sharp,
          () => unawaited(actions.moveSelected(context, selection)),
        ),
        action(
          'Trash',
          'Move to trash',
          Symbols.delete_sharp,
          () => actions.trashSelected(context, selection),
          color: scheme.error,
        ),
      ],
    ];
    final head = [
      IconButton(
        tooltip: 'Done',
        icon: const Icon(Symbols.close_sharp),
        onPressed: selection.clear,
      ),
      Expanded(
        child: Text(
          count == 0 ? 'Select notebooks' : '$count selected',
          style: theme.textTheme.labelLarge,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      TextButton(
        onPressed: () => all ? selection.selectAll(const []) : selection.selectAll(visible),
        child: Text(all ? 'Select none' : 'Select all'),
      ),
    ];
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gaps.lg, 0, Gaps.lg, Gaps.lg),
        child: Align(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: FloatingPanel(
              padding: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(Gaps.xs),
                child: LayoutBuilder(
                  builder: (context, constraints) => constraints.maxWidth >= _oneRow
                      ? Row(
                          children: [
                            ...head,
                            const SizedBox(width: Gaps.sm),
                            ...commands,
                          ],
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(children: head),
                            Row(children: [for (final c in commands) Expanded(child: c)]),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
