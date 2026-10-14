import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/notebook.dart';
import '../../../ui/adaptive_popover.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/sidebar_item.dart';
import 'open_notebooks.dart';

/// Lists the open notebooks: a popover (REDESIGN §5; a sheet on phones,
/// where it is offered).
Future<void> showTabSwitcher(BuildContext context, OpenNotebooks tabs) {
  return showAdaptivePopover<void>(
    context: context,
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
          for (final tab in tabs.tabs) _TabRow(tabs: tabs, tab: tab),
        ],
      ),
    ),
  );
}

/// An open notebook's row: the current one carries the margin rule and a
/// bold label (DESIGN §6), no plate.
class _TabRow extends StatelessWidget {
  const _TabRow({required this.tabs, required this.tab});

  final OpenNotebooks tabs;
  final OpenTab tab;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = tab.id == tabs.activeId;
    final hit = Targets.barHit(context);
    return CustomPaint(
      foregroundPainter: current ? MarginRulePainter(scheme.primary) : null,
      child: ListTile(
        key: ValueKey('switcher-${tab.id}'),
        selected: current,
        selectedColor: scheme.onSurface,
        selectedTileColor: Colors.transparent,
        // The ✕'s glyph mirrors the leading icon: on the content edge, its
        // button's padding in the row's.
        contentPadding: EdgeInsetsDirectional.only(
          start: Gaps.lg,
          end: Gaps.lg - (hit - Glyphs.bar) / 2,
        ),
        leading: Icon(
          tab.kind == NotebookKind.canvas ? Symbols.gesture_sharp : Symbols.menu_book_sharp,
          fill: current ? 1 : 0,
        ),
        title: Text(
          tab.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: current ? const TextStyle(fontWeight: AppTheme.currentWeight) : null,
        ),
        trailing: SizedBox.square(
          dimension: hit,
          child: IconButton(
            tooltip: 'Close tab',
            onPressed: () => tabs.close(tab.id),
            icon: const Icon(Symbols.close_sharp),
          ),
        ),
        onTap: () {
          Navigator.of(context).pop();
          tabs.activate(tab.id);
        },
      ),
    );
  }
}
