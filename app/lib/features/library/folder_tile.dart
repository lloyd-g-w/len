import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../domain/folder.dart';
import '../../ui/app_theme.dart';
import 'library_actions.dart';
import 'library_drag.dart';
import 'library_draggable.dart';
import 'library_menus.dart';

/// A folder in the library's folder row: a compact tile with the folder
/// glyph in its colour, the name and a count. Opens on tap, accepts
/// dropped notebooks and folders, can itself be dragged into another
/// folder, and offers its menu on right-click, long-press or the ⋯ (shown
/// on hover; always on touch).
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

  /// About how wide tiles are; the row stretches them to fill it.
  static const double width = 200;

  /// The narrowest a tile gets at 1× text (scaled with the text).
  static const double minWidth = 150;

  @override
  State<FolderTile> createState() => _FolderTileState();
}

class _FolderTileState extends State<FolderTile> {
  bool _hovered = false;
  bool _menuOpen = false;

  Folder get _folder => widget.folder;

  Future<void> _showMenu({Offset? at, BuildContext? anchor}) async {
    setState(() => _menuOpen = true);
    final action = anchor != null
        ? await showMenuBelow(anchor, items: folderMenuItems)
        : await showContextMenuAt(context, items: folderMenuItems, at: at);
    if (mounted) setState(() => _menuOpen = false);
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
        feedback: DragFeedback(width: 200, child: _tile(context, active: false, feedback: true)),
        onLongPressMenu: () => unawaited(_showMenu()),
        child: _tile(context, active: active),
      ),
    );
  }

  Widget _tile(BuildContext context, {required bool active, bool feedback = false}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final radius = BorderRadius.circular(Radii.sm);
    final showMore = !feedback && (Targets.touchFirst || _hovered || _menuOpen);
    return AnimatedScale(
      scale: active ? 1.03 : 1,
      duration: Motion.fast,
      child: AnimatedContainer(
        duration: Motion.fast,
        // Grows with large text: the name and caption, plus padding.
        height: math.max(56, MediaQuery.textScalerOf(context).scale(20 + 16) + Gaps.lg),
        decoration: BoxDecoration(
          color: active
              ? scheme.primary.withValues(alpha: 0.12)
              : feedback
              ? Surfaces.raised(theme.brightness)
              : _hovered
              ? scheme.surfaceContainer
              : scheme.surfaceContainerLow,
          borderRadius: radius,
          boxShadow: feedback ? Shadows.high(theme.brightness) : null,
        ),
        // Painted over the tile rather than inset, so the outline never
        // narrows the name (no outlines in light mode, REDESIGN §1.1).
        foregroundDecoration: BoxDecoration(
          borderRadius: radius,
          border: active
              ? Border.all(color: scheme.primary, width: 1.5)
              : dark
              ? Border.all(color: scheme.outlineVariant)
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: () => widget.actions.controller.openFolder(_folder.id),
            onSecondaryTapUp: (d) => unawaited(_showMenu(at: d.globalPosition)),
            onHover: (h) => setState(() => _hovered = h),
            child: Padding(
              padding: const EdgeInsets.only(left: Gaps.sm + Gaps.xxs, right: Gaps.xxs),
              child: Row(
                children: [
                  Icon(Symbols.folder_rounded, fill: 1, color: Color(_folder.color), size: 36),
                  const SizedBox(width: Gaps.sm),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _folder.name,
                          style: theme.textTheme.labelLarge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(widget.subtitle, style: theme.textTheme.bodySmall, maxLines: 1),
                      ],
                    ),
                  ),
                  if (!feedback)
                    AnimatedOpacity(
                      opacity: showMore ? 1 : 0,
                      duration: Motion.fast,
                      child: Builder(
                        builder: (anchor) => IconButton(
                          tooltip: 'More',
                          iconSize: Glyphs.bar,
                          constraints: BoxConstraints(
                            minWidth: Targets.of(context, 32),
                            minHeight: Targets.touch,
                          ),
                          padding: EdgeInsets.zero,
                          color: scheme.onSurfaceVariant,
                          icon: const Icon(Symbols.more_horiz_rounded),
                          onPressed: () => unawaited(_showMenu(anchor: anchor)),
                        ),
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
