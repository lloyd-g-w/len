import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../domain/folder.dart';
import '../../ui/app_theme.dart';
import '../../ui/section_label.dart';
import '../../ui/sidebar_item.dart';
import '../../ui/sync_status_button.dart';
import 'library_actions.dart';
import 'library_controller.dart';
import 'library_drag.dart';
import 'library_menus.dart';

/// Navigation sidebar for tablets and desktop (the drawer on phones):
/// sections, the folder tree (all drop targets), sync status and settings.
class LibrarySidebar extends StatefulWidget {
  const LibrarySidebar({
    super.key,
    required this.actions,
    required this.onOpenSettings,
    this.onNavigate,
    this.width = LibrarySidebar.defaultWidth,
  });

  /// The sidebar's width beside the content (REDESIGN §3).
  static const double defaultWidth = 248;

  final LibraryActions actions;
  final VoidCallback onOpenSettings;

  /// Called after a section or folder is opened from here (the drawer
  /// closes).
  final VoidCallback? onNavigate;
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
    // Always reveal the open folder and its subfolders.
    for (final f in c.breadcrumbs) {
      _expanded.add(f.id);
    }
    return Container(
      width: widget.width,
      decoration: BoxDecoration(
        color: Surfaces.chrome(scheme),
        border: Border(right: Surfaces.chromeEdge(scheme)),
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
                  _sectionItem(LibrarySection.library, Symbols.auto_stories_rounded, 'Library'),
                  _sectionItem(
                    LibrarySection.favorites,
                    Symbols.star_rounded,
                    'Favourites',
                    count: c.favoriteCount,
                  ),
                  _sectionItem(
                    LibrarySection.trash,
                    Symbols.delete_rounded,
                    'Trash',
                    count: c.trash.length,
                  ),
                  const SizedBox(height: Gaps.lg),
                  Padding(
                    padding: const EdgeInsets.only(left: Gaps.md, bottom: Gaps.xs),
                    child: Row(
                      children: [
                        Expanded(child: SectionLabel('Folders')),
                        IconButton(
                          tooltip: 'New folder',
                          iconSize: Glyphs.menu,
                          visualDensity: VisualDensity.compact,
                          color: scheme.onSurfaceVariant,
                          icon: const Icon(Symbols.create_new_folder_rounded),
                          onPressed: () {
                            // The drawer closes first: one overlay at a time.
                            widget.onNavigate?.call();
                            unawaited(widget.actions.createFolder(context));
                          },
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
                      icon: Symbols.settings_rounded,
                      label: 'Settings',
                      onTap: widget.onOpenSettings,
                    ),
                  ),
                  SyncStatusButton(
                    sync: c.services.sync,
                    onConfigure: widget.onOpenSettings,
                    // Large text: Settings keeps its name; sync its icon.
                    caption: MediaQuery.textScalerOf(context).scale(1) < 1.15,
                  ),
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
        icon: icon,
        label: label,
        count: count,
        selected: selected,
        dropActive: active,
        onTap: () {
          c.showSection(section);
          widget.onNavigate?.call();
        },
      ),
    );
  }

  void _trash(String notebookId) {
    final notebook = _controller.services.notebooks.get(notebookId);
    if (notebook != null) unawaited(widget.actions.trash(context, notebook));
  }

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
                      Symbols.chevron_right_rounded,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                )
              : null,
        ),
        icon: Symbols.folder_rounded,
        filled: true,
        iconColor: Color(folder.color),
        label: folder.name,
        selected: c.section == LibrarySection.library && c.folderId == folder.id,
        dropActive: active,
        onTap: () {
          c.openFolder(folder.id);
          widget.onNavigate?.call();
        },
        onSecondaryTapUp: (d) => unawaited(_folderMenu(context, folder, d.globalPosition)),
        onLongPress: () => unawaited(_folderMenu(context, folder, null)),
      ),
    );
  }

  Future<void> _folderMenu(BuildContext context, Folder folder, Offset? at) async {
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
                colors: [Color.lerp(AppTheme.seed, Colors.white, 0.15)!, AppTheme.seed],
              ),
              boxShadow: Shadows.low(theme.brightness),
            ),
            child: Icon(Symbols.gesture_rounded, size: Glyphs.bar, color: Colors.white),
          ),
          const SizedBox(width: Gaps.md),
          Text('Len', style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }
}
