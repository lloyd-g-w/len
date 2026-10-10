import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/preferences.dart';
import '../../ui/app_theme.dart';
import 'library_actions.dart';
import 'library_controller.dart';
import 'library_drag.dart';

/// Title, breadcrumbs and tools (search, sort, view) above the library
/// content.
class LibraryHeader extends StatelessWidget {
  const LibraryHeader({
    super.key,
    required this.actions,
    required this.searchController,
    required this.searchFocus,
    required this.compact,
    this.trailing = const [],
  });

  final LibraryActions actions;
  final TextEditingController searchController;
  final FocusNode searchFocus;

  /// Phone layout: search goes on its own row.
  final bool compact;

  /// Extra actions at the end of the title row (phone: sync).
  final List<Widget> trailing;

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
          icon: const Icon(Icons.create_new_folder_outlined),
          onPressed: () => unawaited(actions.createFolder(context)),
        ),
      if (_c.section != LibrarySection.trash) _SortButton(controller: _c),
      if (_c.visibleNotebooks.isNotEmpty)
        IconButton(
          tooltip: 'Select notebooks',
          isSelected: actions.selection.active,
          icon: const Icon(Icons.check_circle_outline_rounded),
          selectedIcon: const Icon(Icons.check_circle_rounded),
          onPressed: () =>
              actions.selection.active ? actions.selection.clear() : actions.selection.start(),
        ),
      _LayoutToggle(controller: _c),
      if (_c.section == LibrarySection.trash && _c.trash.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(left: Gaps.sm),
          child: OutlinedButton.icon(
            onPressed: () => unawaited(actions.emptyTrash(context)),
            icon: const Icon(Icons.delete_sweep_outlined, size: 18),
            label: const Text('Empty Trash'),
          ),
        ),
    ];
    final folders = _c.visibleFolders.length;
    String plural(int n, String one) => '$n ${n == 1 ? one : '${one}s'}';
    final subtitle = switch (_c.section) {
      LibrarySection.trash => 'Restore notebooks or delete them forever.',
      _ when _c.isSearching => '${plural(count + folders, 'result')} across all folders',
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
                Expanded(child: titleBlock),
                ...trailing,
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
                Expanded(child: titleBlock),
                const SizedBox(width: Gaps.lg),
                SizedBox(width: 280, child: search),
                const SizedBox(width: Gaps.sm),
                ...tools,
                ...trailing,
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
          decoration: InputDecoration(
            hintText: 'Search',
            contentPadding: EdgeInsets.zero,
            prefixIcon: Icon(Icons.search_rounded, color: scheme.onSurfaceVariant, size: 20),
            suffixIcon: controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    iconSize: 18,
                    icon: const Icon(Icons.close_rounded),
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

class _SortButton extends StatelessWidget {
  const _SortButton({required this.controller});

  final LibraryController controller;

  static String label(LibrarySort s) => switch (s) {
    LibrarySort.edited => 'Last edited',
    LibrarySort.created => 'Date created',
    LibrarySort.name => 'Name',
  };

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<LibrarySort>(
      tooltip: 'Sort: ${label(controller.sort)}',
      icon: const Icon(Icons.sort_rounded),
      initialValue: controller.sort,
      onSelected: (s) => controller.sort = s,
      itemBuilder: (_) => [
        for (final s in LibrarySort.values)
          CheckedPopupMenuItem(value: s, checked: s == controller.sort, child: Text(label(s))),
      ],
    );
  }
}

class _LayoutToggle extends StatelessWidget {
  const _LayoutToggle({required this.controller});

  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
    final grid = controller.layout == LibraryLayout.grid;
    return IconButton(
      tooltip: grid ? 'Show as list' : 'Show as grid',
      icon: AnimatedSwitcher(
        duration: Motion.fast,
        child: Icon(
          grid ? Icons.view_agenda_outlined : Icons.grid_view_rounded,
          key: ValueKey(grid),
        ),
      ),
      onPressed: () => controller.layout = grid ? LibraryLayout.list : LibraryLayout.grid,
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
            Icon(Icons.chevron_right_rounded, size: 18, color: scheme.outline),
          ],
        ],
      ),
    );
  }
}
