import 'package:flutter/material.dart';

import '../../../domain/notebook_page.dart';
import '../../../ui/menus.dart';

/// Something the user asked for on one page in the overview.
enum PageCommand {
  insertBefore('Add page before', Icons.vertical_align_top_rounded),
  insertAfter('Add page after', Icons.vertical_align_bottom_rounded),
  duplicate('Duplicate', Icons.copy_rounded),
  template('Change template…', Icons.grid_on_rounded),
  saveAsTemplate('Save as template…', Icons.dashboard_customize_outlined),
  bookmark('Bookmark', Icons.bookmark_border_rounded),
  delete('Delete', Icons.delete_outline_rounded);

  const PageCommand(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Callbacks through which the overview edits the notebook. Each returns
/// once the change is stored; the overview then reloads its pages.
class OverviewHandlers {
  const OverviewHandlers({
    required this.load,
    required this.command,
    required this.move,
    this.deleteMany,
  });

  /// Current pages in order.
  final List<NotebookPage> Function() load;

  /// Runs a command on a page (may show dialogs).
  final Future<void> Function(BuildContext context, PageCommand command, NotebookPage page) command;

  /// Moves a page to a new index.
  final void Function(NotebookPage page, int toIndex) move;

  /// Deletes several pages as one undoable step. Without it, the overview
  /// runs [PageCommand.delete] on each page.
  final Future<void> Function(BuildContext context, List<NotebookPage> pages)? deleteMany;
}

/// The options menu of [page].
List<PopupMenuEntry<PageCommand>> pageMenuItems(NotebookPage page) => [
  for (final c in PageCommand.values) ...[
    if (c == PageCommand.delete) const PopupMenuDivider(),
    MenuRow(
      value: c,
      icon: c == PageCommand.bookmark && page.bookmarked ? Icons.bookmark_remove_outlined : c.icon,
      label: c == PageCommand.bookmark && page.bookmarked ? 'Remove bookmark' : c.label,
      destructive: c == PageCommand.delete,
    ),
  ],
];
