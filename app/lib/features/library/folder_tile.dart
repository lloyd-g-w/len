import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/folder.dart';
import '../../ui/app_theme.dart';
import 'library_actions.dart';
import 'library_drag.dart';
import 'library_draggable.dart';
import 'library_menus.dart';

/// A folder in the library content area. Opens on tap, accepts dropped
/// notebooks and folders, and can itself be dragged into another folder.
class FolderTile extends StatefulWidget {
  const FolderTile({
    super.key,
    required this.folder,
    required this.subtitle,
    required this.actions,
  });

  final Folder folder;
  final String subtitle;
  final LibraryActions actions;

  @override
  State<FolderTile> createState() => _FolderTileState();
}

class _FolderTileState extends State<FolderTile> {
  bool _hovered = false;

  Folder get _folder => widget.folder;

  Future<void> _showMenu({Offset? at, BuildContext? anchor}) async {
    final action = await showContextMenuAt(anchor ?? context, items: folderMenuItems, at: at);
    if (action != null && mounted) await widget.actions.onFolderAction(context, _folder, action);
  }

  @override
  Widget build(BuildContext context) {
    final actions = widget.actions;
    return LibraryDropTarget(
      canAccept: (item) => actions.canDrop(item, _folder.id),
      onAccept: (item) => actions.drop(context, item, _folder.id),
      builder: (context, active) => LibraryDraggable(
        item: LibraryDragItem.folder(_folder.id),
        feedback: DragFeedback(width: 220, child: _body(context, active: false, feedback: true)),
        onLongPressMenu: () => unawaited(_showMenu()),
        child: _body(context, active: active),
      ),
    );
  }

  Widget _body(BuildContext context, {required bool active, bool feedback = false}) =>
      LayoutBuilder(
        // Narrow tiles (phones) drop the menu button; long-press still works.
        builder: (context, constraints) =>
            _tile(context, active: active, feedback: feedback, narrow: constraints.maxWidth < 200),
      );

  Widget _tile(
    BuildContext context, {
    required bool active,
    required bool feedback,
    required bool narrow,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = Color(_folder.color);
    final highlighted = active || _hovered;
    return AnimatedScale(
      scale: active ? 1.04 : 1,
      duration: Motion.fast,
      child: AnimatedContainer(
        duration: Motion.medium,
        curve: Motion.standard,
        decoration: BoxDecoration(
          color: active
              ? scheme.primaryContainer
              : highlighted
              ? scheme.surfaceContainer
              : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(Radii.control + 2),
          border: Border.all(
            color: active ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.6),
            width: active ? 1.6 : 1,
          ),
          boxShadow: feedback || highlighted ? Shadows.low(theme.brightness) : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.control + 2),
            onTap: () => widget.actions.controller.openFolder(_folder.id),
            onSecondaryTapUp: (d) => unawaited(_showMenu(at: d.globalPosition)),
            onHover: (h) => setState(() => _hovered = h),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Gaps.md, Gaps.sm, Gaps.xs, Gaps.sm),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(
                        alpha: theme.brightness == Brightness.dark ? 0.22 : 0.14,
                      ),
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
                    child: Icon(Icons.folder_rounded, color: color, size: 22),
                  ),
                  const SizedBox(width: Gaps.md),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _folder.name,
                          style: theme.textTheme.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(widget.subtitle, style: theme.textTheme.bodySmall, maxLines: 1),
                      ],
                    ),
                  ),
                  if (!feedback && !narrow)
                    Builder(
                      builder: (anchor) => IconButton(
                        tooltip: 'Folder options',
                        iconSize: 18,
                        color: scheme.onSurfaceVariant,
                        icon: const Icon(Icons.more_horiz_rounded),
                        onPressed: () => unawaited(_showMenu(anchor: anchor)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
