import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/notebook.dart';
import '../../ui/app_theme.dart';
import 'library_actions.dart';
import 'library_drag.dart';
import 'library_draggable.dart';
import 'library_menus.dart';
import 'notebook_cover.dart';

/// A notebook in the library grid: its cover (live preview) with the title
/// and a subtitle below. Lifts on hover, opens on tap, offers its menu on
/// right-click, long-press or the "More" button, and can be dragged onto
/// folders.
class NotebookCard extends StatefulWidget {
  const NotebookCard({
    super.key,
    required this.notebook,
    required this.subtitle,
    required this.actions,
  });

  final Notebook notebook;
  final String subtitle;
  final LibraryActions actions;

  @override
  State<NotebookCard> createState() => _NotebookCardState();
}

class _NotebookCardState extends State<NotebookCard> {
  bool _hovered = false;
  bool _focused = false;

  Notebook get _notebook => widget.notebook;

  /// Opens the menu at [at] (global), else under [anchor] or the card.
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
    final brightness = theme.brightness;
    final lifted = _hovered || _focused;
    final cover = AnimatedContainer(
      duration: Motion.medium,
      curve: Motion.standard,
      transform: Matrix4.translationValues(0, lifted ? -4 : 0, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.cover),
        boxShadow: lifted ? Shadows.high(brightness) : Shadows.low(brightness),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.cover),
          onTap: () => unawaited(widget.actions.openNotebook(context, _notebook)),
          onSecondaryTapUp: (d) => unawaited(_showMenu(at: d.globalPosition)),
          onHover: (h) => setState(() => _hovered = h),
          onFocusChange: (f) {
            setState(() => _focused = f);
            widget.actions.controller.focusedNotebookId = f ? _notebook.id : null;
          },
          child: NotebookCover.of(_notebook),
        ),
      ),
    );
    return Semantics(
      label: _notebook.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: LibraryDraggable(
              item: LibraryDragItem.notebook(_notebook.id),
              feedback: DragFeedback(
                width: 110,
                height: 110 / 0.72,
                child: NotebookCover.of(_notebook),
              ),
              onLongPressMenu: () => unawaited(_showMenu()),
              child: AnimatedScale(scale: _focused ? 1.02 : 1, duration: Motion.fast, child: cover),
            ),
          ),
          const SizedBox(height: Gaps.sm + 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: Gaps.xxs),
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
              ),
              SizedBox(
                width: 28,
                height: 28,
                child: Builder(
                  builder: (anchor) => IconButton(
                    tooltip: 'More',
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    color: theme.colorScheme.onSurfaceVariant,
                    icon: const Icon(Icons.more_horiz_rounded),
                    onPressed: () => unawaited(_showMenu(anchor: anchor)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
