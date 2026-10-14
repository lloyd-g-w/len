import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/notebook_page.dart';
import '../../../ui/menus.dart';

/// A command on one page: the one page menu, shown whole in the editor's
/// ⋯ → Page and in an overview tile's ⋯, in this order and with these
/// names (UX_AUDIT R9-3). [menu] lists the rows; [insertWithTemplate] is
/// "Add page after" held down (or right-clicked).
enum PageCommand {
  insertAfter('Add page after', Symbols.add_sharp),
  duplicate('Duplicate page', Symbols.library_add_sharp),
  moveTo('Move or copy page…', Symbols.move_group_sharp),
  bookmark('Bookmark page', Symbols.bookmark_add_sharp),
  template('Change template…', Symbols.grid_on_sharp),
  saveAsTemplate('Save as template…', Symbols.dashboard_customize_sharp),
  delete('Delete page', Symbols.delete_sharp),

  /// Chooses a template, then adds a page with it after the page.
  insertWithTemplate('Add page with template…', Symbols.note_add_sharp);

  const PageCommand(this._label, this._icon);
  final String _label;
  final IconData _icon;

  /// The page menu's rows, in order.
  static const List<PageCommand> menu = [
    insertAfter,
    duplicate,
    moveTo,
    bookmark,
    template,
    saveAsTemplate,
    delete,
  ];

  /// The row's name for a page that is [bookmarked] or not.
  String labelFor({bool bookmarked = false}) =>
      this == bookmark && bookmarked ? 'Remove bookmark' : _label;

  /// The row's glyph for a page that is [bookmarked] or not.
  IconData iconFor({bool bookmarked = false}) =>
      this == bookmark && bookmarked ? Symbols.bookmark_remove_sharp : _icon;

  /// Drawn in `error`, after a divider.
  bool get destructive => this == delete;

  /// What holding the row down (or right-clicking it) runs instead.
  PageCommand? get alternate => this == insertAfter ? insertWithTemplate : null;

  /// The screen-reader action offering [alternate] on the row (its name
  /// without the ellipsis: "Add page with template"), since the long press
  /// and the secondary click are pointer gestures.
  String? get alternateAction => alternate?._label.replaceAll('…', '');
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
    this.sendMany,
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

  /// Moves or copies [pages] to another notebook the user picks. Without
  /// it, the selection offers no Move or copy.
  final Future<void> Function(BuildContext context, List<NotebookPage> pages)? sendMany;
}

/// The page menu of [page] (an overview tile's ⋯).
List<PopupMenuEntry<PageCommand>> pageMenuItems(NotebookPage page) => [
  for (final c in PageCommand.menu) ...[
    if (c.destructive) const PopupMenuDivider(),
    MenuRow(
      value: c,
      alternate: c.alternate,
      alternateAction: c.alternateAction,
      icon: c.iconFor(bookmarked: page.bookmarked),
      label: c.labelFor(bookmarked: page.bookmarked),
      destructive: c.destructive,
    ),
  ],
];
