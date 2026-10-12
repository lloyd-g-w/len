import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/notebook.dart';
import '../../../ui/app_theme.dart';
import 'open_notebooks.dart';

/// Phone counterpart of the tab strip: a button showing how many notebooks
/// are open, opening a sheet to switch between or close them.
class TabSwitcherButton extends StatelessWidget {
  const TabSwitcherButton({super.key, required this.tabs});

  final OpenNotebooks tabs;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tabs,
      builder: (context, _) =>
          _CountButton(count: tabs.length, onPressed: () => showTabSwitcher(context, tabs)),
    );
  }
}

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
                tab.kind == NotebookKind.canvas ? Symbols.gesture_rounded : Symbols.menu_book_rounded,
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

/// A rounded square with the number of open notebooks, like a browser's
/// tab counter.
class _CountButton extends StatelessWidget {
  const _CountButton({required this.count, required this.onPressed});

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return IconButton(
      tooltip: 'Open notebooks',
      onPressed: onPressed,
      style: IconButton.styleFrom(
        fixedSize: const Size(40, 40),
        minimumSize: const Size(40, 40),
        padding: EdgeInsets.zero,
      ),
      icon: Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 1.8),
          borderRadius: BorderRadius.circular(Radii.xs),
        ),
        child: Text(
          '$count',
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      ),
    );
  }
}
