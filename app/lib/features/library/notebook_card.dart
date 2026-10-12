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

/// A notebook in the library grid: its cover (live preview) with a
/// two-line title and a caption below. Opens on tap (Ctrl / Shift-click
/// selects, as on a desktop), offers its menu on right-click, long-press or
/// the ⋯ by the title (shown on hover or focus; always on touch), and can be
/// dragged onto folders.
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

  /// Height of everything below the cover: gap, two title lines, caption.
  static double captionHeight(TextScaler scaler) => Gaps.sm + scaler.scale(20 * 2 + 16) + Gaps.xs;

  @override
  State<NotebookCard> createState() => _NotebookCardState();
}

class _NotebookCardState extends State<NotebookCard> {
  bool _hovered = false;
  bool _focused = false;
  bool _menuOpen = false;

  Notebook get _notebook => widget.notebook;
  bool get _selecting => widget.actions.selection.active;

  /// Opens the notebook, or toggles it in selection mode.
  void _tap() {
    final actions = widget.actions;
    if (actions.selectWithModifiers(_notebook.id)) return;
    if (_selecting) {
      actions.selection.toggle(_notebook.id);
      return;
    }
    unawaited(
      actions.openNotebook(context, _notebook, from: actions.covers.originOf(context, _notebook)),
    );
  }

  bool get _selected => widget.actions.selection.contains(_notebook.id);

  /// Opens the menu at [at] (global), else under [anchor] or the card.
  Future<void> _showMenu({Offset? at, BuildContext? anchor}) async {
    setState(() => _menuOpen = true);
    final items = notebookMenuItems(_notebook);
    final action = anchor != null && at == null
        ? await showMenuBelow(anchor, items: items)
        : await showContextMenuAt(context, items: items, at: at);
    if (mounted) setState(() => _menuOpen = false);
    if (action != null && mounted) {
      await widget.actions.onNotebookAction(context, _notebook, action);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final lifted = (_hovered || _focused) && !_selecting;
    final radius = BorderRadius.circular(Radii.sm);
    final cover = AnimatedContainer(
      duration: Motion.medium,
      curve: Motion.standard,
      transform: Matrix4.translationValues(0, lifted ? -2 : 0, 0),
      decoration: BoxDecoration(
        borderRadius: radius,
        // `raised`: a shadow in light mode, a hairline in dark mode.
        boxShadow: lifted ? Shadows.high(theme.brightness) : Shadows.low(theme.brightness),
      ),
      foregroundDecoration: dark
          ? BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: scheme.outlineVariant),
            )
          : null,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: _tap,
          onSecondaryTapUp: (d) => unawaited(_showMenu(at: d.globalPosition)),
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
    final showMore = Targets.touchFirst || _hovered || _focused || _menuOpen;
    return Semantics(
      label: '${_notebook.title}, ${widget.subtitle}',
      selected: _selecting && _selected,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
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
                // Trashed notebooks look faded but recognisable.
                child: _notebook.isTrashed ? fadedCover(cover) : cover,
              ),
            ),
            // A fixed caption area, so every cover in a row is as tall.
            SizedBox(
              height: NotebookCard.captionHeight(MediaQuery.textScalerOf(context)),
              child: Padding(
                padding: const EdgeInsets.only(top: Gaps.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      // The title is part of the target too.
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _tap,
                        onSecondaryTapUp: (d) => unawaited(_showMenu(at: d.globalPosition)),
                        child: Padding(
                          padding: const EdgeInsets.only(left: Gaps.xxs),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _notebook.title,
                                style: theme.textTheme.labelLarge,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
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
                    if (!_selecting)
                      AnimatedOpacity(
                        opacity: showMore ? 1 : 0,
                        duration: Motion.fast,
                        child: SizedBox(
                          width: Targets.touchFirst ? 40 : 32,
                          height: Targets.touchFirst ? 36 : 28,
                          child: Builder(
                            builder: (anchor) => IconButton(
                              tooltip: 'More',
                              padding: EdgeInsets.zero,
                              iconSize: Glyphs.bar,
                              color: scheme.onSurfaceVariant,
                              // Reachable by keyboard and screen readers even
                              // while hidden.
                              icon: const Icon(Symbols.more_horiz_rounded),
                              onPressed: () => unawaited(_showMenu(anchor: anchor)),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
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
