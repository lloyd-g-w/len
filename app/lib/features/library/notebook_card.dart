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
  bool get _selecting => widget.actions.selection.active;

  /// Opens the notebook, or toggles it in selection mode.
  void _tap() => _selecting
      ? widget.actions.selection.toggle(_notebook.id)
      : unawaited(
          widget.actions.openNotebook(
            context,
            _notebook,
            from: widget.actions.covers.originOf(context, _notebook),
          ),
        );
  bool get _selected => widget.actions.selection.contains(_notebook.id);

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
        borderRadius: BorderRadius.circular(Radii.sm),
        boxShadow: lifted ? Shadows.high(brightness) : Shadows.low(brightness),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.sm),
          onTap: _tap,
          onSecondaryTapUp: (d) => unawaited(_showMenu(at: d.globalPosition)),
          onHover: (h) => setState(() => _hovered = h),
          onFocusChange: (f) {
            setState(() => _focused = f);
            widget.actions.controller.setNotebookFocused(_notebook.id, f);
          },
          child: CoverAnchor(
            locator: widget.actions.covers,
            notebookId: _notebook.id,
            child: Stack(
              fit: StackFit.expand,
              children: [
                NotebookCover.of(_notebook),
                if (_selecting) SelectionMark(selected: _selected),
              ],
            ),
          ),
        ),
      ),
    );
    return Semantics(
      label: '${_notebook.title}, ${widget.subtitle}',
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
              child: AnimatedScale(
                scale: _focused ? 1.02 : 1,
                duration: Motion.fast,
                // Trashed notebooks look faded but recognisable.
                child: _notebook.isTrashed ? fadedCover(cover) : cover,
              ),
            ),
          ),
          const SizedBox(height: Gaps.sm + 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                // The title is part of the target too.
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _tap,
                  child: Padding(
                    padding: const EdgeInsets.only(left: Gaps.xxs),
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
                ),
              ),
              SizedBox(
                width: 36,
                height: 36,
                child: Builder(
                  builder: (anchor) => IconButton(
                    tooltip: 'More',
                    padding: EdgeInsets.zero,
                    iconSize: Glyphs.bar,
                    color: theme.colorScheme.onSurfaceVariant,
                    icon: const Icon(Symbols.more_horiz_rounded),
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

/// Desaturates and fades [cover] (trashed notebooks).
Widget fadedCover(Widget cover) => Opacity(
  opacity: 0.8,
  child: ColorFiltered(
    colorFilter: const ColorFilter.matrix([
      0.5, 0.4, 0.1, 0, 20, //
      0.2, 0.7, 0.1, 0, 20, //
      0.2, 0.4, 0.4, 0, 20, //
      0, 0, 0, 1, 0, //
    ]),
    child: cover,
  ),
);
