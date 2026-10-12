import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/notebook.dart';
import '../../../ui/app_theme.dart';
import 'open_notebooks.dart';

/// Lists the open notebooks in a bottom sheet.
Future<void> showTabSwitcher(BuildContext context, OpenNotebooks tabs) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (context) => ListenableBuilder(
      listenable: tabs,
      builder: (context, _) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(Gaps.sm, 0, Gaps.sm, Gaps.lg),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gaps.lg, 0, Gaps.lg, Gaps.sm),
            child: Text('Open notebooks', style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final tab in tabs.tabs)
            ListTile(
              key: ValueKey('switcher-${tab.id}'),
              selected: tab.id == tabs.activeId,
              leading: Icon(
                tab.kind == NotebookKind.canvas
                    ? Symbols.gesture_rounded
                    : Symbols.menu_book_rounded,
              ),
              title: Text(tab.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                tooltip: 'Close tab',
                onPressed: () => tabs.close(tab.id),
                icon: const Icon(Symbols.close_rounded),
              ),
              onTap: () {
                Navigator.of(context).pop();
                tabs.activate(tab.id);
              },
            ),
        ],
      ),
    ),
  );
}
