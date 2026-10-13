import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/notebook_page.dart';
import '../../../ui/menus.dart';

/// Something the user asked for on one page in the overview.
enum PageCommand {
  insertAfter('Add page after', Symbols.add_sharp),
  duplicate('Duplicate', Symbols.library_add_sharp),
  template('Change template…', Symbols.grid_on_sharp),
  saveAsTemplate('Save as template…', Symbols.dashboard_customize_sharp),
  bookmark('Bookmark', Symbols.bookmark_sharp),
  delete('Delete', Symbols.delete_sharp);

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
    this.bookmarkMany,
    this.deleteMany,
    this.duplicateMany,
    this.exportMany,
    this.templateMany,
  });

  /// Current pages in order.
  final List<NotebookPage> Function() load;

  /// Runs a command on a page (may show dialogs).
  final Future<void> Function(BuildContext context, PageCommand command, NotebookPage page) command;

  /// Moves a page to a new index.
  final void Function(NotebookPage page, int toIndex) move;

  /// Bookmarks several pages ([on]) or removes their bookmarks, as one
  /// undoable step. Without it, the overview toggles each page.
  final void Function(List<NotebookPage> pages, {required bool on})? bookmarkMany;

  /// Deletes several pages as one undoable step. Without it, the overview
  /// runs [PageCommand.delete] on each page.
  final Future<void> Function(BuildContext context, List<NotebookPage> pages)? deleteMany;

  /// Duplicates several pages (each copy right after its page) as one
  /// undoable step. Without it, the overview runs [PageCommand.duplicate]
  /// on each page.
  final Future<void> Function(BuildContext context, List<NotebookPage> pages)? duplicateMany;

  /// Opens the export sheet with [pages] as its page range. Without it,
  /// the selection offers no Export.
  final Future<void> Function(BuildContext context, List<NotebookPage> pages)? exportMany;

  /// Asks for a template and applies it to [pages] as one undoable step.
  /// Without it, the selection offers no Template.
  final Future<void> Function(BuildContext context, List<NotebookPage> pages)? templateMany;
}

/// The options menu of [page].
List<PopupMenuEntry<PageCommand>> pageMenuItems(NotebookPage page) => [
  for (final c in PageCommand.values) ...[
    if (c == PageCommand.delete) const PopupMenuDivider(),
    MenuRow(
      value: c,
      icon: c == PageCommand.bookmark && page.bookmarked ? Symbols.bookmark_remove_sharp : c.icon,
      label: c == PageCommand.bookmark && page.bookmarked ? 'Remove bookmark' : c.label,
      destructive: c == PageCommand.delete,
    ),
  ],
];
