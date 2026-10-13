import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../domain/notebook.dart';
import '../../domain/preferences.dart';
import '../../ui/app_theme.dart';
import '../../ui/menus.dart';
import 'library_actions.dart';
import 'library_controller.dart';
import 'library_drag.dart';

/// Title (or breadcrumbs) with a caption, and the tools beside it: search
/// (a 280-dp field when wide, a 🔍 that opens a field over the title when
/// narrow), ⊕▾ New (wide only), ⇅ View and, in the trash, Empty trash.
class LibraryHeader extends StatefulWidget {
  const LibraryHeader({
    super.key,
    required this.actions,
    required this.searchController,
    required this.searchFocus,
    required this.compact,
    this.leading,
  });

  final LibraryActions actions;
  final TextEditingController searchController;
  final FocusNode searchFocus;

  /// Phone layout: no ⊕▾ (the FAB creates), search behind 🔍.
  final bool compact;

  /// Before the title (phone: the drawer button).
  final Widget? leading;

  /// The narrowest header with a search field always shown.
  static const double searchFieldMinWidth = 560;

  @override
  State<LibraryHeader> createState() => _LibraryHeaderState();
}

class _LibraryHeaderState extends State<LibraryHeader> {
  /// Narrow layouts: the search field is open over the title.
  bool _searchOpen = false;

  LibraryActions get _actions => widget.actions;
  LibraryController get _c => _actions.controller;

  @override
  void initState() {
    super.initState();
    widget.searchFocus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(LibraryHeader old) {
    super.didUpdateWidget(old);
    if (old.searchFocus != widget.searchFocus) {
      old.searchFocus.removeListener(_onFocus);
      widget.searchFocus.addListener(_onFocus);
    }
  }

  @override
  void dispose() {
    widget.searchFocus.removeListener(_onFocus);
    super.dispose();
  }

  /// Ctrl+F (or a tap) focusing the field opens it; leaving it empty closes it.
  void _onFocus() {
    final open = widget.searchFocus.hasFocus || _c.isSearching;
    if (open != _searchOpen) setState(() => _searchOpen = open);
  }

  void _openSearch() {
    setState(() => _searchOpen = true);
    widget.searchFocus.requestFocus();
  }

  void _closeSearch() {
    widget.searchController.clear();
    _c.query = '';
    widget.searchFocus.unfocus();
    setState(() => _searchOpen = false);
  }

  String get _title => switch (_c.section) {
    LibrarySection.library => _c.folder?.name ?? 'Library',
    LibrarySection.favorites => 'Favourites',
    LibrarySection.trash => 'Trash',
  };

  String get _caption {
    final count = _c.visibleNotebooks.length;
    final folders = _c.visibleFolders.length;
    String plural(int n, String one) => '$n ${n == 1 ? one : '${one}s'}';
    return switch (_c.section) {
      // The library also lists matches inside notebooks (features/search).
      LibrarySection.library when _c.isSearching => 'Titles and contents, across all folders',
      _ when _c.isSearching => '${plural(count, 'notebook')} across all folders',
      // Phones have no room for the note (Empty trash… says it again).
      LibrarySection.trash when count > 0 && !widget.compact =>
        '${plural(count, 'notebook')} · deleted forever '
            'when you empty the trash',
      _ when count == 0 && folders == 0 => 'Empty',
      _ => [
        if (folders > 0) plural(folders, 'folder'),
        if (count > 0 || folders == 0) plural(count, 'notebook'),
      ].join(' · '),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: Motion.medium,
          layoutBuilder: (current, previous) =>
              Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
          child: Semantics(
            key: ValueKey(_title),
            header: true,
            child: Text(
              _title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge,
            ),
          ),
        ),
        const SizedBox(height: Gaps.xxs),
        Text(
          _caption,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wideSearch =
            !widget.compact && constraints.maxWidth >= LibraryHeader.searchFieldMinWidth;
        final search = _SearchField(
          controller: widget.searchController,
          focus: widget.searchFocus,
          actions: _actions,
          onClose: wideSearch ? null : _closeSearch,
        );
        final searchOpen = !wideSearch && (_searchOpen || _c.isSearching);
        final tools = <Widget>[
          if (wideSearch) ...[
            SizedBox(width: 280, child: search),
            const SizedBox(width: Gaps.sm),
          ] else if (!searchOpen)
            IconButton(
              tooltip: 'Search',
              icon: const Icon(Symbols.search_rounded),
              onPressed: _openSearch,
            ),
          if (!widget.compact && _c.section == LibrarySection.library) _NewMenu(actions: _actions),
          _ViewMenu(actions: _actions),
          if (_c.section == LibrarySection.trash && _c.trash.isNotEmpty)
            _emptyTrash(theme, wideSearch),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_c.section == LibrarySection.library && _c.folderId != null && !searchOpen) ...[
              _Breadcrumbs(actions: _actions),
              const SizedBox(height: Gaps.xxs),
            ],
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Row(
                children: [
                  if (widget.leading case final leading? when !searchOpen) ...[
                    leading,
                    const SizedBox(width: Gaps.xs),
                  ],
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: Motion.fast,
                      transitionBuilder: (child, animation) =>
                          FadeTransition(opacity: animation, child: child),
                      layoutBuilder: (current, previous) =>
                          Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
                      child: searchOpen
                          ? KeyedSubtree(key: const ValueKey('search'), child: search)
                          : KeyedSubtree(key: const ValueKey('title'), child: titleBlock),
                    ),
                  ),
                  const SizedBox(width: Gaps.md),
                  ...tools,
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _emptyTrash(ThemeData theme, bool wide) {
    void empty() => unawaited(_actions.emptyTrash(context));
    if (!wide) {
      return IconButton(
        tooltip: 'Empty trash…',
        color: theme.colorScheme.error,
        icon: const Icon(Symbols.delete_sweep_rounded),
        onPressed: empty,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: Gaps.xs),
      child: TextButton.icon(
        style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
        onPressed: empty,
        icon: const Icon(Symbols.delete_sweep_rounded, size: Glyphs.menu),
        label: const Text('Empty trash…'),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focus,
    required this.actions,
    this.onClose,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final LibraryActions actions;

  /// Narrow layouts: ✕ closes the field (else it only clears it).
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 40,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => TextField(
          controller: controller,
          focusNode: focus,
          onChanged: (q) => actions.controller.query = q,
          textInputAction: TextInputAction.search,
          textAlignVertical: TextAlignVertical.center,
          decoration: InputDecoration(
            hintText: 'Search',
            contentPadding: EdgeInsets.zero,
            prefixIcon: Icon(
              Symbols.search_rounded,
              color: scheme.onSurfaceVariant,
              size: Glyphs.bar,
            ),
            suffixIcon: controller.text.isEmpty && onClose == null
                ? null
                : IconButton(
                    tooltip: onClose == null || controller.text.isNotEmpty
                        ? 'Clear search'
                        : 'Close search',
                    iconSize: Glyphs.menu,
                    icon: const Icon(Symbols.close_rounded),
                    onPressed: () {
                      if (controller.text.isEmpty) {
                        onClose?.call();
                        return;
                      }
                      controller.clear();
                      actions.controller.query = '';
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

/// What ⊕▾ (and a long press on the phone's ⊕) creates.
enum NewChoice { notebook, canvas, pdf, folder }

/// The rows of ⊕▾: New notebook, New canvas, Import PDF…, New folder.
List<PopupMenuEntry<NewChoice>> newMenuItems() => const [
  MenuRow(
    value: NewChoice.notebook,
    icon: Symbols.menu_book_rounded,
    label: 'New notebook',
    shortcut: 'Ctrl+N',
  ),
  MenuRow(value: NewChoice.canvas, icon: Symbols.all_inclusive_rounded, label: 'New canvas'),
  MenuRow(value: NewChoice.pdf, icon: Symbols.picture_as_pdf_rounded, label: 'Import PDF…'),
  PopupMenuDivider(),
  MenuRow(
    value: NewChoice.folder,
    icon: Symbols.create_new_folder_rounded,
    label: 'New folder…',
    shortcut: 'Ctrl+Shift+N',
  ),
];

/// Creates what [choice] says.
Future<void> runNewChoice(BuildContext context, LibraryActions actions, NewChoice choice) =>
    switch (choice) {
      NewChoice.notebook => actions.createNotebook(context),
      NewChoice.canvas => actions.createNotebook(context, kind: NotebookKind.canvas),
      NewChoice.pdf => actions.importPdf(context),
      NewChoice.folder => actions.createFolder(context),
    };

/// ⊕▾ (wide screens).
class _NewMenu extends StatelessWidget {
  const _NewMenu({required this.actions});

  final LibraryActions actions;

  @override
  Widget build(BuildContext context) {
    return MenuIconButton<NewChoice>(
      tooltip: 'New',
      icon: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Symbols.add_circle_rounded),
          Icon(Symbols.arrow_drop_down_rounded, size: Glyphs.menu),
        ],
      ),
      items: newMenuItems,
      onSelected: (choice) => unawaited(runNewChoice(context, actions, choice)),
    );
  }
}

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

/// ⇅ View: sort (not in the trash), grid or list, and Select….
class _ViewMenu extends StatelessWidget {
  const _ViewMenu({required this.actions});

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
      icon: const Icon(Symbols.swap_vert_rounded),
      onSelected: (choice) => switch (choice) {
        _Sort(:final sort) => c.sort = sort,
        _Layout(:final layout) => c.layout = layout,
        _Select() => actions.selection.start(),
      },
      items: () => [
        if (c.section != LibrarySection.trash) ...[
          for (final s in LibrarySort.values)
            MenuRow(value: _Sort(s), label: _label(s), checked: s == c.sort),
          const PopupMenuDivider(),
        ],
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
          const MenuRow(value: _Select(), icon: Symbols.check_circle_rounded, label: 'Select…'),
        ],
      ],
    );
  }
}

/// "Library › School › Maths": every segment but the last navigates, and
/// accepts dropped items.
class _Breadcrumbs extends StatelessWidget {
  const _Breadcrumbs({required this.actions});

  final LibraryActions actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final path = actions.controller.breadcrumbs;
    final segments = <({String? id, String name})>[
      (id: null, name: 'Library'),
      for (final f in path.take(path.length - 1)) (id: f.id, name: f.name),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final s in segments) ...[
            LibraryDropTarget(
              canAccept: (item) => actions.canDrop(item, s.id),
              onAccept: (item) => actions.drop(context, item, s.id),
              builder: (context, active) => AnimatedContainer(
                duration: Motion.fast,
                decoration: BoxDecoration(
                  color: active ? scheme.primary.withValues(alpha: 0.12) : Colors.transparent,
                  borderRadius: BorderRadius.circular(Radii.xs),
                ),
                child: TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: Gaps.sm),
                    foregroundColor: scheme.onSurfaceVariant,
                    textStyle: theme.textTheme.labelLarge,
                  ),
                  onPressed: () => actions.controller.openFolder(s.id),
                  child: Text(s.name),
                ),
              ),
            ),
            Icon(Symbols.chevron_right_rounded, size: Glyphs.menu, color: scheme.outline),
          ],
        ],
      ),
    );
  }
}
