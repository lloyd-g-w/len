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

  @override
  State<NotebookListTile> createState() => _NotebookListTileState();
}

class _NotebookListTileState extends State<NotebookListTile> {
  bool _hovered = false;

  Notebook get _notebook => widget.notebook;

  Future<void> _showMenu({Offset? at, BuildContext? anchor}) async {
    final action = await showContextMenuAt(
      anchor ?? context,
      items: notebookMenuItems(_notebook),
      at: at,
    );
    if (action != null && mounted) {
      await widget.actions.onNotebookAction(context, _notebook, action);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final row = AnimatedContainer(
      duration: Motion.fast,
      decoration: BoxDecoration(
        color: _hovered ? scheme.surfaceContainerLow : Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.sm),
          onTap: widget.actions.selection.active
              ? () => widget.actions.selection.toggle(_notebook.id)
              : () => unawaited(
                  widget.actions.openNotebook(
                    context,
                    _notebook,
                    from: widget.actions.covers.originOf(context, _notebook),
                  ),
                ),
          onSecondaryTapUp: (d) => unawaited(_showMenu(at: d.globalPosition)),
          onHover: (h) => setState(() => _hovered = h),
          onFocusChange: (f) => widget.actions.controller.setNotebookFocused(_notebook.id, f),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gaps.md, vertical: Gaps.sm),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Radii.xs),
                    boxShadow: Shadows.low(theme.brightness),
                  ),
                  child: CoverAnchor(
                    locator: widget.actions.covers,
                    notebookId: _notebook.id,
                    child: SizedBox(
                      width: 40,
                      height: 40 / 0.72,
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
                        style: theme.textTheme.titleSmall,
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
                if (!_notebook.isTrashed)
                  IconButton(
                    tooltip: _notebook.favorite ? 'Remove from favourites' : 'Add to favourites',
                    icon: Icon(
                      Symbols.star_rounded,
                      fill: _notebook.favorite ? 1 : 0,
                      color: _notebook.favorite ? const Color(0xFFF5A524) : scheme.onSurfaceVariant,
                    ),
                    onPressed: () =>
                        widget.actions.controller.setFavorite(_notebook.id, !_notebook.favorite),
                  ),
                Builder(
                  builder: (anchor) => IconButton(
                    tooltip: 'More',
                    color: scheme.onSurfaceVariant,
                    icon: const Icon(Symbols.more_horiz_rounded),
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
