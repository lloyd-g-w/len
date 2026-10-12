import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/notebook.dart';
import '../chrome/bar_button.dart';
import '../chrome/canvas_guard.dart';
import '../tabs/open_notebooks.dart';

/// The top bar's split view button (large screens): opens a second pane
/// with this notebook (another place in it) or another open notebook;
/// while split, offers linked tools, swapping and closing.
class SplitViewButton extends StatelessWidget {
  const SplitViewButton({super.key, required this.tabs, required this.notebookId});

  final OpenNotebooks tabs;

  /// The notebook of the editor showing the button.
  final String notebookId;

  @override
  Widget build(BuildContext context) {
    final split = tabs.splitId != null;
    return ChromeMenuAnchor(
      menuChildren: split ? _splitItems() : _openItems(),
      builder: (context, menu, _) => BarButton(
        tooltip: split ? 'Split view' : 'Open in split view',
        icon: Symbols.vertical_split_rounded,
        selectedIcon: Symbols.vertical_split_rounded,
        selected: split,
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
      ),
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
