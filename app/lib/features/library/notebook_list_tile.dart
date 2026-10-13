import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../domain/notebook.dart';
import '../../ui/app_theme.dart';
import 'cover_locator.dart';
import 'library_actions.dart';
import 'library_drag.dart';
import 'library_draggable.dart';
import 'library_menus.dart';
import 'notebook_cover.dart';
import 'selection/selection_mark.dart';

/// A notebook as a row in the library's list view.
class NotebookListTile extends StatefulWidget {
  const NotebookListTile({
    super.key,
    required this.notebook,
    required this.subtitle,
    required this.actions,
  });

  final Notebook notebook;
  final String subtitle;
  final LibraryActions actions;

  /// Where the title starts: the hairlines between rows start here. The
  /// cover sits on the screen's margin column, like the grid's first cover.
  static const double textInset = Gaps.xxs + _coverWidth + Gaps.lg;

  static const double _coverWidth = 40;

  @override
  State<NotebookListTile> createState() => _NotebookListTileState();
}

class _NotebookListTileState extends State<NotebookListTile> {
  bool _hovered = false;

  Notebook get _notebook => widget.notebook;

  Future<void> _showMenu({Offset? at, BuildContext? anchor}) async {
    final items = notebookMenuItems(_notebook);
    final action = anchor != null
        ? await showMenuBelow(anchor, items: items)
        : await showContextMenuAt(context, items: items, at: at);
    if (action != null && mounted) {
      await widget.actions.onNotebookAction(context, _notebook, action);
    }
  }

  /// Opens the notebook; toggles it in selection mode; Ctrl / Shift-click
  /// selects.
  void _tap() {
    final actions = widget.actions;
    if (actions.selectWithModifiers(_notebook.id)) return;
    if (actions.selection.active) {
      actions.selection.toggle(_notebook.id);
      return;
    }
    unawaited(
      actions.openNotebook(context, _notebook, from: actions.covers.originOf(context, _notebook)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final row = AnimatedContainer(
      duration: Motion.fast,
      decoration: BoxDecoration(
        color: _hovered ? Surfaces.hovered(scheme) : Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.xs),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.xs),
          onTap: _tap,
          onSecondaryTapUp: (d) => unawaited(_showMenu(at: d.globalPosition)),
          onHover: (h) => setState(() => _hovered = h),
          onFocusChange: (f) => widget.actions.controller.setNotebookFocused(_notebook.id, f),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Gaps.xxs, Gaps.sm, Gaps.xs, Gaps.sm),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Radii.sm),
                    boxShadow: Shadows.low(theme.brightness),
                  ),
                  child: CoverAnchor(
                    locator: widget.actions.covers,
                    notebookId: _notebook.id,
                    child: SizedBox(
                      width: NotebookListTile._coverWidth,
                      height: NotebookListTile._coverWidth / 0.72,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          NotebookCover.of(_notebook, showFavorite: false),
                          if (widget.actions.selection.active)
                            SelectionMark(
                              selected: widget.actions.selection.contains(_notebook.id),
                              compact: true,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: Gaps.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _notebook.title,
                        style: theme.textTheme.labelLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: Gaps.xxs),
                      Text(
                        widget.subtitle,
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // A star marks favourites (as on covers); the toggle shows
                // on hover, and on touch it is in ⋯.
                if (!_notebook.isTrashed)
                  Visibility(
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    visible: _notebook.favorite || _hovered,
                    child: IconButton(
                      tooltip: _notebook.favorite ? 'Remove from favourites' : 'Add to favourites',
                      icon: Icon(
                        Symbols.star_sharp,
                        fill: _notebook.favorite ? 1 : 0,
                        color: _notebook.favorite ? Palette.favourite : scheme.onSurfaceVariant,
                      ),
                      onPressed: () =>
                          widget.actions.controller.setFavorite(_notebook.id, !_notebook.favorite),
                    ),
                  ),
                Builder(
                  builder: (anchor) => IconButton(
                    tooltip: 'More',
                    color: scheme.onSurfaceVariant,
                    icon: const Icon(Symbols.more_horiz_sharp),
                    onPressed: () => unawaited(_showMenu(anchor: anchor)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return LibraryDraggable(
      item: LibraryDragItem.notebook(_notebook.id),
      feedback: DragFeedback(width: 80, height: 80 / 0.72, child: NotebookCover.of(_notebook)),
      onLongPressMenu: () => unawaited(_showMenu()),
      child: row,
    );
  }
}
