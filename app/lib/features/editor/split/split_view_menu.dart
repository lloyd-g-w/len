import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/notebook.dart';
import '../tabs/open_notebooks.dart';

/// The "⋯" menu's split view entry (large panes): opens a second pane with
/// this notebook (another place in it) or another open notebook; while
/// split, offers swapping and closing.
class SplitViewMenu extends StatelessWidget {
  const SplitViewMenu({super.key, required this.tabs, required this.notebookId});

  final OpenNotebooks tabs;

  /// The notebook of the editor showing the menu.
  final String notebookId;

  @override
  Widget build(BuildContext context) {
    final split = tabs.splitId != null;
    return SubmenuButton(
      leadingIcon: const Icon(Symbols.vertical_split_rounded),
      menuChildren: split ? _splitItems() : _openItems(),
      child: Text(split ? 'Split view' : 'Open in split view'),
    );
  }

  List<Widget> _openItems() => [
    MenuItemButton(
      leadingIcon: const Icon(Symbols.auto_stories_rounded),
      onPressed: () => tabs.openSplit(notebookId),
      child: const Text('This notebook, side by side'),
    ),
    if (tabs.length > 1) const Divider(),
    for (final tab in tabs.tabs)
      if (tab.id != notebookId)
        MenuItemButton(
          leadingIcon: Icon(
            tab.kind == NotebookKind.canvas ? Symbols.gesture_rounded : Symbols.menu_book_rounded,
          ),
          onPressed: () => tabs.openSplit(tab.id),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Text(tab.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
  ];

  List<Widget> _splitItems() => [
    if (tabs.splitId != tabs.activeId)
      MenuItemButton(
        leadingIcon: const Icon(Symbols.swap_horiz_rounded),
        onPressed: tabs.swapSplit,
        child: const Text('Swap panes'),
      ),
    MenuItemButton(
      leadingIcon: const Icon(Symbols.close_rounded),
      onPressed: tabs.closeSplit,
      child: const Text('Close split view'),
    ),
  ];
}
