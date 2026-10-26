import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../domain/preferences.dart';
import 'library_actions.dart';
import 'library_controller.dart';
import 'library_menus.dart';

/// What the ⇅ View menu changes.
sealed class _ViewChoice {
  const _ViewChoice();
}

class _Sort extends _ViewChoice {
  const _Sort(this.sort);
  final LibrarySort sort;
}

class _Layout extends _ViewChoice {
  const _Layout(this.layout);
  final LibraryLayout layout;
}

class _Select extends _ViewChoice {
  const _Select();
}

/// ⇅ View: sort (not in the trash), grid or list, and Select.
class LibraryViewMenu extends StatelessWidget {
  const LibraryViewMenu({super.key, required this.actions});

  final LibraryActions actions;

  static String _label(LibrarySort s) => switch (s) {
    LibrarySort.edited => 'Last edited',
    LibrarySort.created => 'Created',
    LibrarySort.name => 'Name',
  };

  @override
  Widget build(BuildContext context) {
    final c = actions.controller;
    return MenuIconButton<_ViewChoice>(
      tooltip: 'View',
      // Sort, layout and Select: a neutral glyph, not a sorting one.
      icon: const Icon(Symbols.tune_rounded),
      onSelected: (choice) => switch (choice) {
        _Sort(:final sort) => c.sort = sort,
        _Layout(:final layout) => c.layout = layout,
        _Select() => actions.startSelection(context),
      },
      items: () => [
        if (c.section != LibrarySection.trash) ...[
          const MenuHeading('Sort by'),
          for (final s in LibrarySort.values)
            MenuRow(value: _Sort(s), label: _label(s), checked: s == c.sort),
          const PopupMenuDivider(),
        ],
        const MenuHeading('Show as'),
        MenuRow(
          value: const _Layout(LibraryLayout.grid),
          icon: Symbols.grid_view_rounded,
          label: 'Grid',
          checked: c.layout == LibraryLayout.grid,
        ),
        MenuRow(
          value: const _Layout(LibraryLayout.list),
          icon: Symbols.view_agenda_rounded,
          label: 'List',
          checked: c.layout == LibraryLayout.list,
        ),
        if (c.visibleNotebooks.isNotEmpty && !actions.selection.active) ...[
          const PopupMenuDivider(),
          const MenuRow(value: _Select(), icon: Symbols.check_circle_rounded, label: 'Select'),
        ],
      ],
    );
  }
}
