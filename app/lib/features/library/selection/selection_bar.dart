import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/floating_panel.dart';
import '../library_actions.dart';
import '../library_controller.dart';
import 'library_selection.dart';
import 'selection_actions.dart';

/// Floating bar of the library's selection mode: count, select all, and
/// the batch actions (favourite, move, trash — or restore and delete in the
/// trash), within thumb reach at the bottom.
class LibrarySelectionBar extends StatelessWidget {
  const LibrarySelectionBar({super.key, required this.actions, required this.selection});

  final LibraryActions actions;
  final LibrarySelection selection;

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
      String tooltip,
      IconData icon,
      VoidCallback onPressed, {
      Color? color,
      bool always = false,
      bool filled = false,
    }) => IconButton(
      tooltip: tooltip,
      color: color,
      icon: Icon(icon, fill: filled ? 1 : 0),
      onPressed: some || always ? onPressed : null,
    );
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
                padding: const EdgeInsets.symmetric(horizontal: Gaps.xs, vertical: Gaps.xs),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Done',
                      icon: const Icon(Symbols.close_rounded),
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
                    action(
                      all ? 'Select none' : 'Select all',
                      all ? Symbols.deselect_rounded : Symbols.select_all_rounded,
                      () => all ? selection.selectAll(const []) : selection.selectAll(visible),
                      always: true,
                    ),
                    if (trash) ...[
                      action(
                        'Restore',
                        Symbols.restore_rounded,
                        () => actions.restoreSelected(selection),
                      ),
                      action(
                        'Delete forever',
                        Symbols.delete_forever_rounded,
                        () => unawaited(actions.deleteSelectedForever(context, selection)),
                        color: scheme.error,
                      ),
                    ] else ...[
                      action(
                        allStarred ? 'Remove from favourites' : 'Add to favourites',
                        Symbols.star_rounded,
                        () => actions.favoriteSelected(selection),
                        filled: allStarred,
                      ),
                      action(
                        'Move to folder…',
                        Symbols.drive_file_move_rounded,
                        () => unawaited(actions.moveSelected(context, selection)),
                      ),
                      action(
                        'Move to trash',
                        Symbols.delete_rounded,
                        () => actions.trashSelected(context, selection),
                        color: scheme.error,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
