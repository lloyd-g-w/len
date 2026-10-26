import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../domain/folder.dart';
import '../../ui/app_theme.dart';
import '../../ui/context_menu_keys.dart';
import 'library_actions.dart';
import 'library_drag.dart';
import 'library_draggable.dart';
import 'library_menus.dart';

/// A folder in the library's ruled folder row: the folder glyph in its
/// colour, the name and a count, without a plate. Opens on tap, accepts
/// dropped notebooks and folders, can itself be dragged into another
/// folder, and offers its menu on right-click, long-press or the ⋯ (shown
/// on hover; always on touch).
class FolderTile extends StatefulWidget {
  const FolderTile({
    super.key,
    required this.folder,
    required this.subtitle,
    required this.actions,
    this.dense = false,
  });

  final Folder folder;
  final String subtitle;
  final LibraryActions actions;

  /// Short windows: as low as a touch target, beside the library's title.
  final bool dense;

  /// The narrowest a tile gets at 1× text (scaled with the text).
  static const double minWidth = 150;

  /// Where the name starts: past the padding, the glyph and its gap.
  static const double textInset = Gaps.xxs + Glyphs.bar + Gaps.md;

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
        child: ContextMenuKeys(
          onMenu: () => unawaited(_showMenu()),
          child: _tile(context, active: active),
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, {required bool active, bool feedback = false}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(Radii.xs);
    final showMore = !feedback && (Targets.touchFirst || _hovered || _menuOpen);
    // No plate (DESIGN §6.1): a name in the ruled row. Hover is the ink
    // overlay; a drop target is marked like a sidebar row; the dragged copy
    // is a slip.
    final moreWidth = Targets.of(context, 32);
    final content = Padding(
      padding: const EdgeInsets.only(left: Gaps.xxs, right: Gaps.xxs),
      child: Row(
        children: [
          Icon(Symbols.folder_rounded, fill: 1, color: Color(_folder.color), size: Glyphs.bar),
          const SizedBox(width: Gaps.md), // FolderTile.textInset
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
          // Room for the ⋯, which lies over the tile.
          if (!feedback) SizedBox(width: moreWidth),
        ],
      ),
    );
    final tile = AnimatedContainer(
      duration: Motion.fast,
      // Grows with large text: the name and caption, plus padding.
      height: widget.dense
          ? math.max(Targets.touch, MediaQuery.textScalerOf(context).scale(20 + 16) + Gaps.sm)
          : math.max(52, MediaQuery.textScalerOf(context).scale(20 + 16) + Gaps.lg),
      decoration: feedback
          ? Surfaces.overlayDecoration(scheme, radius: Radii.sm)
          : BoxDecoration(
              color: active
                  ? scheme.primary.withValues(alpha: 0.12)
                  : _hovered || _menuOpen
                  ? Surfaces.hovered(scheme)
                  : Colors.transparent,
              borderRadius: radius,
              border: active ? Border.all(color: scheme.primary, width: 1.5) : null,
            ),
      child: feedback
          ? content
          // For screen readers the tile is a button named by its name and
          // caption, the ⋯ a button beside it (reachable while hidden):
          // whether or not the ⋯ shows, the tile stays a button.
          : Stack(
              fit: StackFit.expand,
              children: [
                Semantics(
                  container: true,
                  button: true,
                  label: '${_folder.name}\n${widget.subtitle}',
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      borderRadius: radius,
                      onTap: () => widget.actions.controller.openFolder(_folder.id),
                      onSecondaryTapUp: (d) => unawaited(_showMenu(at: d.globalPosition)),
                      child: ExcludeSemantics(child: content),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: Gaps.xxs,
                  child: AnimatedOpacity(
                    opacity: showMore ? 1 : 0,
                    duration: Motion.fast,
                    alwaysIncludeSemantics: true,
                    child: Center(
                      child: Builder(
                        builder: (anchor) => IconButton(
                          tooltip: 'More',
                          iconSize: Glyphs.bar,
                          constraints: BoxConstraints(
                            minWidth: moreWidth,
                            maxWidth: moreWidth,
                            minHeight: Targets.touch,
                          ),
                          padding: EdgeInsets.zero,
                          color: scheme.onSurfaceVariant,
                          icon: const Icon(Symbols.more_horiz_rounded),
                          onPressed: () => unawaited(_showMenu(anchor: anchor)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
    // The tile's hover covers its ⋯ too (which lies over the ink).
    return feedback
        ? tile
        : MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: tile,
          );
  }
}
