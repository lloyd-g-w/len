import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/folder.dart';
import '../../ui/app_theme.dart';
import '../../ui/sync_status_button.dart';
import 'library_actions.dart';
import 'library_controller.dart';
import 'library_drag.dart';
import 'library_menus.dart';
import 'sidebar_item.dart';

/// Navigation sidebar for tablets and desktop: sections, the folder tree
/// (all drop targets), sync status and settings.
class LibrarySidebar extends StatefulWidget {
  const LibrarySidebar({
    super.key,
    required this.actions,
    required this.onOpenSettings,
    this.width = 264,
  });

  final LibraryActions actions;
  final VoidCallback onOpenSettings;
  final double width;

  @override
  State<LibrarySidebar> createState() => _LibrarySidebarState();
}

class _LibrarySidebarState extends State<LibrarySidebar> {
  /// Folders whose children are shown in the tree.
  final Set<String> _expanded = {};

  LibraryController get _controller => widget.actions.controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = _controller;
    // Always reveal the open folder.
    for (final f in c.breadcrumbs.reversed.skip(1)) {
      _expanded.add(f.id);
    }
    return Container(
      width: widget.width,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(right: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Brand(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: Gaps.md),
                children: [
                  _sectionItem(LibrarySection.library, Icons.auto_stories_outlined, 'Library'),
                  _sectionItem(
                    LibrarySection.favorites,
                    Icons.star_outline_rounded,
                    'Favourites',
                    count: c.favoriteCount,
                  ),
                  _sectionItem(
                    LibrarySection.trash,
                    Icons.delete_outline_rounded,
                    'Trash',
                    count: c.trash.length,
                  ),
                  const SizedBox(height: Gaps.lg),
                  Padding(
                    padding: const EdgeInsets.only(left: Gaps.md, bottom: Gaps.xs),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'FOLDERS',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              letterSpacing: 1.1,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'New folder',
                          iconSize: 18,
                          visualDensity: VisualDensity.compact,
                          color: scheme.onSurfaceVariant,
                          icon: const Icon(Icons.create_new_folder_outlined),
                          onPressed: () => unawaited(widget.actions.createFolder(context)),
                        ),
                      ],
                    ),
                  ),
                  if (c.allFolders.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Gaps.md, 0, Gaps.md, Gaps.md),
                      child: Text(
                        'Group notebooks into folders — drag them here.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ..._tree(null, 0),
                ],
              ),
            ),
            Divider(height: 1, color: scheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.fromLTRB(Gaps.md, Gaps.sm, Gaps.md, Gaps.md),
              child: Row(
                children: [
                  Expanded(
                    child: SidebarItem(
                      icon: Icons.settings_outlined,
                      label: 'Settings',
                      onTap: widget.onOpenSettings,
                    ),
                  ),
                  SyncStatusButton(sync: c.services.sync, onConfigure: widget.onOpenSettings),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionItem(LibrarySection section, IconData icon, String label, {int? count}) {
    final c = _controller;
    final selected =
        c.section == section && (section != LibrarySection.library || c.folderId == null);
    return LibraryDropTarget(
      canAccept: (item) => switch (section) {
        LibrarySection.library => widget.actions.canDrop(item, null),
        _ => !item.isFolder,
      },
      onAccept: (item) => switch (section) {
        LibrarySection.library => widget.actions.drop(context, item, null),
        LibrarySection.favorites => c.setFavorite(item.id, true),
        LibrarySection.trash => _trash(item.id),
      },
      builder: (context, active) => SidebarItem(
        icon: selected ? _filled(icon) : icon,
        label: label,
        count: count,
        selected: selected,
        dropActive: active,
        onTap: () => c.showSection(section),
      ),
    );
  }

  void _trash(String notebookId) {
    final notebook = _controller.services.notebooks.get(notebookId);
    if (notebook != null) unawaited(widget.actions.trash(context, notebook));
  }

  static IconData _filled(IconData icon) => switch (icon) {
    Icons.auto_stories_outlined => Icons.auto_stories_rounded,
    Icons.star_outline_rounded => Icons.star_rounded,
    Icons.delete_outline_rounded => Icons.delete_rounded,
    _ => icon,
  };

  Iterable<Widget> _tree(String? parentId, int depth) sync* {
    for (final folder in _controller.childrenOf(parentId)) {
      yield _folderItem(folder, depth);
      if (_expanded.contains(folder.id)) yield* _tree(folder.id, depth + 1);
    }
  }

  Widget _folderItem(Folder folder, int depth) {
    final c = _controller;
    final hasChildren = c.childrenOf(folder.id).isNotEmpty;
    final expanded = _expanded.contains(folder.id);
    final scheme = Theme.of(context).colorScheme;
    return LibraryDropTarget(
      key: ValueKey('tree-${folder.id}'),
      canAccept: (item) => widget.actions.canDrop(item, folder.id),
      onAccept: (item) => widget.actions.drop(context, item, folder.id),
      builder: (context, active) => SidebarItem(
        indent: depth * 16.0,
        leading: SizedBox(
          width: 22,
          child: hasChildren
              ? InkResponse(
                  radius: 14,
                  onTap: () => setState(
                    () => expanded ? _expanded.remove(folder.id) : _expanded.add(folder.id),
                  ),
                  child: AnimatedRotation(
                    turns: expanded ? 0.25 : 0,
                    duration: Motion.fast,
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                )
              : null,
        ),
        icon: Icons.folder_rounded,
        iconColor: Color(folder.color),
        label: folder.name,
        selected: c.section == LibrarySection.library && c.folderId == folder.id,
        dropActive: active,
        onTap: () => c.openFolder(folder.id),
        onSecondaryTapUp: (d) => unawaited(_folderMenu(context, folder, d.globalPosition)),
      ),
    );
  }

  Future<void> _folderMenu(BuildContext context, Folder folder, Offset at) async {
    final action = await showContextMenuAt(context, items: folderMenuItems, at: at);
    if (action != null && context.mounted) {
      await widget.actions.onFolderAction(context, folder, action);
    }
  }
}

/// App mark and name at the top of the sidebar.
class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gaps.xl - 2, Gaps.xl, Gaps.lg, Gaps.lg),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.sm),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color.lerp(scheme.primary, Colors.white, 0.15)!, scheme.primary],
              ),
              boxShadow: Shadows.low(theme.brightness),
            ),
            child: Icon(Icons.gesture_rounded, size: 20, color: scheme.onPrimary),
          ),
          const SizedBox(width: Gaps.md),
          Text('Len', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
