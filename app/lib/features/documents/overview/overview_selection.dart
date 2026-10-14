import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/selection_bar.dart';
import 'page_commands.dart';

/// What can be done to the pages selected in the overview.
enum SelectionAction { bookmark, duplicate, send, template, export, delete }

/// The overview's selection mode in the shared [SelectionBar] (the
/// library's too, UX_AUDIT R8-13): done, count, select all, and the
/// actions for the selected pages; Template, Bookmark and Duplicate give
/// way to ⋯ in that order on phones.
class PageSelectionBar extends StatelessWidget {
  const PageSelectionBar({
    super.key,
    required this.count,
    required this.total,
    required this.onClose,
    required this.onSelectAll,
    required this.onAction,
    this.allBookmarked = false,
    this.offered = const {
      SelectionAction.bookmark,
      SelectionAction.duplicate,
      SelectionAction.delete,
    },
  });

  final int count;

  /// How many pages there are (all selected: Select none).
  final int total;
  final VoidCallback onClose;
  final VoidCallback onSelectAll;

  /// The actions shown (the notebook's handlers decide).
  final Set<SelectionAction> offered;

  /// Whether every selected page is bookmarked: the action removes them.
  final bool allBookmarked;
  final ValueChanged<SelectionAction> onAction;

  SelectionCommand _command(SelectionAction a) => switch (a) {
    SelectionAction.bookmark => SelectionCommand(
      icon: allBookmarked ? Symbols.bookmark_remove_sharp : Symbols.bookmark_sharp,
      label: allBookmarked ? 'Remove bookmark' : 'Bookmark',
      overflow: 2,
      onPressed: () => onAction(a),
    ),
    SelectionAction.duplicate => SelectionCommand(
      icon: Symbols.library_add_sharp,
      label: 'Duplicate',
      overflow: 3,
      onPressed: () => onAction(a),
    ),
    SelectionAction.send => SelectionCommand(
      icon: PageCommand.moveTo.icon,
      label: PageCommand.moveTo.label,
      onPressed: () => onAction(a),
    ),
    SelectionAction.template => SelectionCommand(
      icon: Symbols.grid_on_sharp,
      label: 'Template…',
      tooltip: 'Change template…',
      overflow: 1,
      onPressed: () => onAction(a),
    ),
    SelectionAction.export => SelectionCommand(
      icon: Symbols.ios_share_sharp,
      label: 'Export…',
      onPressed: () => onAction(a),
    ),
    SelectionAction.delete => SelectionCommand(
      icon: Symbols.delete_sharp,
      label: 'Delete',
      destructive: true,
      // No question: the deletion offers Undo (UX_AUDIT R9-6).
      onPressed: () => onAction(a),
    ),
  };

  @override
  Widget build(BuildContext context) => SelectionBar(
    title: count == 0 ? 'Select pages' : '$count selected',
    onDone: onClose,
    allSelected: count == total,
    onSelectAll: onSelectAll,
    enabled: count > 0,
    commands: [
      for (final a in SelectionAction.values)
        if (offered.contains(a)) _command(a),
    ],
  );
}
