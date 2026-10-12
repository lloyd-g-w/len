import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../domain/preferences.dart';
import '../../ui/app_theme.dart';
import '../../ui/menus.dart';
import 'library_actions.dart';
import 'library_controller.dart';
import 'library_drag.dart';

/// Title, breadcrumbs and tools (search, new folder, ⇅ view) above the library
/// content.
class LibraryHeader extends StatelessWidget {
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

  /// Phone layout: search goes on its own row.
  final bool compact;

  /// Before the title (phone: the drawer button).
  final Widget? leading;

  LibraryController get _c => actions.controller;

  String get _title => switch (_c.section) {
    LibrarySection.library => _c.folder?.name ?? 'Library',
    LibrarySection.favorites => 'Favourites',
    LibrarySection.trash => 'Trash',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = _c.visibleNotebooks.length;
    final search = _SearchField(controller: searchController, focus: searchFocus, actions: actions);
    final tools = [
      if (_c.section == LibrarySection.library && !_c.isSearching)
        IconButton(
          tooltip: 'New folder',
          icon: const Icon(Symbols.create_new_folder_rounded),
          onPressed: () => unawaited(actions.createFolder(context)),
        ),
      _ViewMenu(actions: actions),
      if (_c.section == LibrarySection.trash && _c.trash.isNotEmpty)
        if (compact)
          IconButton(
            tooltip: 'Empty trash',
            color: theme.colorScheme.error,
            icon: const Icon(Symbols.delete_sweep_rounded),
            onPressed: () => unawaited(actions.emptyTrash(context)),
          )
        else
          Padding(
            padding: const EdgeInsets.only(left: Gaps.sm),
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
              onPressed: () => unawaited(actions.emptyTrash(context)),
              icon: const Icon(Symbols.delete_sweep_rounded, size: 18),
              label: const Text('Empty trash'),
            ),
          ),
    ];
    final folders = _c.visibleFolders.length;
    String plural(int n, String one) => '$n ${n == 1 ? one : '${one}s'}';
    final subtitle = switch (_c.section) {
      LibrarySection.trash => 'Restore notebooks or delete them forever',
      // The library also lists matches inside notebooks (features/search).
      LibrarySection.library when _c.isSearching => 'Titles and contents, across all folders',
      _ when _c.isSearching => '${plural(count, 'notebook')} across all folders',
      _ when count == 0 && folders == 0 => 'Empty',
      _ => [
        if (folders > 0) plural(folders, 'folder'),
        if (count > 0 || folders == 0) plural(count, 'notebook'),
      ].join(' · '),
    };
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSwitcher(
          duration: Motion.medium,
          layoutBuilder: (current, previous) =>
              Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
          child: Text(
            _title,
            key: ValueKey(_title),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: compact ? theme.textTheme.headlineSmall : theme.textTheme.headlineMedium,
          ),
        ),
        const SizedBox(height: Gaps.xxs),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_c.section == LibrarySection.library && _c.folderId != null) ...[
            _Breadcrumbs(actions: actions),
            const SizedBox(height: Gaps.xs),
          ],
          // Search on its own row when the title would get squeezed.
          if (compact || constraints.maxWidth < 680) ...[
            Row(
              children: [
                if (leading case final leading?) ...[leading, const SizedBox(width: Gaps.xs)],
                Expanded(child: titleBlock),
              ],
            ),
            const SizedBox(height: Gaps.lg),
            Row(
              children: [
                Expanded(child: search),
                ...tools,
              ],
            ),
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (leading case final leading?) ...[leading, const SizedBox(width: Gaps.xs)],
                Expanded(child: titleBlock),
                const SizedBox(width: Gaps.lg),
                SizedBox(width: 280, child: search),
                const SizedBox(width: Gaps.sm),
                ...tools,
              ],
            ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.focus, required this.actions});

  final TextEditingController controller;
  final FocusNode focus;
  final LibraryActions actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
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
            prefixIcon: Icon(Symbols.search_rounded, color: scheme.onSurfaceVariant, size: 20),
            suffixIcon: controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    iconSize: 18,
                    icon: const Icon(Symbols.close_rounded),
                    onPressed: () {
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
    LibrarySort.created => 'Date created',
    LibrarySort.name => 'Name',
  };

  @override
  Widget build(BuildContext context) {
    final c = actions.controller;
    return PopupMenuButton<_ViewChoice>(
      tooltip: 'View',
      icon: const Icon(Symbols.swap_vert_rounded),
      onSelected: (choice) => switch (choice) {
        _Sort(:final sort) => c.sort = sort,
        _Layout(:final layout) => c.layout = layout,
        _Select() => actions.selection.start(),
      },
      itemBuilder: (_) => [
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
          const MenuRow(
            value: _Select(),
            icon: Symbols.check_circle_rounded,
            label: 'Select notebooks',
          ),
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
                  color: active ? scheme.primaryContainer : Colors.transparent,
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
            Icon(Symbols.chevron_right_rounded, size: 18, color: scheme.outline),
          ],
        ],
      ),
    );
  }
}
