import 'dart:async';
import 'dart:math' as math;

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

  /// Width of the ⋯'s button beside the title (its target grows to 48 on
  /// touch, over the title's end).
  static double get _moreWidth => Targets.touchFirst ? 40 : 32;

  /// What the title leaves for the ⋯: its glyph, flush with the cover's
  /// right edge, and a small gap (a narrow cover keeps its title).
  static const double _moreRoom = Glyphs.bar + Gaps.xs;

  /// Height of the ⋯'s button (its glyph level with the title's first
  /// line, at its top).
  static double get _moreHeight => Targets.touchFirst ? 36 : 28;

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
                // Trashed notebooks look faded but recognisable; the
                // selection mark and ring keep their colours.
                if (_notebook.isTrashed)
                  fadedCover(NotebookCover.of(_notebook))
                else
                  NotebookCover.of(_notebook),
                if (_selecting) SelectionMark(selected: _selected),
              ],
            ),
          ),
        ),
      ),
    );
    final showMore = Targets.touchFirst || _hovered || _focused || _menuOpen;
    // One node for the card: the cover takes taps, its title and caption
    // make the label; the ⋯ stays a button of its own.
    return Semantics(
      container: true,
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
                child: cover,
              ),
            ),
            // A fixed caption area, so every cover in a row is as tall.
            SizedBox(
              height: NotebookCard.captionHeight(MediaQuery.textScalerOf(context)),
              child: Padding(
                padding: const EdgeInsets.only(top: Gaps.sm),
                // The ⋯ sits beside the title only; the caption below takes
                // the full width (it would truncate early at large text).
                child: Stack(
                  children: [
                    // The title is part of the target too.
                    Positioned.fill(
                      child: GestureDetector(
                        // The card says its title and caption and takes taps.
                        excludeFromSemantics: true,
                        behavior: HitTestBehavior.opaque,
                        onTap: _tap,
                        onSecondaryTapUp: (d) => unawaited(_showMenu(at: d.globalPosition)),
                        child: Padding(
                          padding: const EdgeInsets.only(left: Gaps.xxs),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: EdgeInsets.only(
                                  right: _selecting ? 0 : NotebookCard._moreRoom,
                                ),
                                child: _CardTitle(_notebook.title),
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
                      Positioned(
                        top: 0,
                        right: 0,
                        child: AnimatedOpacity(
                          opacity: showMore ? 1 : 0,
                          duration: Motion.fast,
                          // A 48-dp target on touch; the glyph keeps its
                          // place beside the title's first line.
                          child: SizedBox(
                            width: Targets.of(context, NotebookCard._moreWidth),
                            height: Targets.of(context, NotebookCard._moreHeight),
                            child: Builder(
                              builder: (anchor) => IconButton(
                                tooltip: 'More',
                                alignment: Alignment.topRight,
                                // Centred on the title's first line (20 dp).
                                padding: EdgeInsets.only(
                                  top: math.max(
                                    0,
                                    (MediaQuery.textScalerOf(context).scale(20) - Glyphs.bar) / 2,
                                  ),
                                ),
                                iconSize: Glyphs.bar,
                                color: scheme.onSurfaceVariant,
                                // Reachable by keyboard and screen readers even
                                // while hidden.
                                icon: const Icon(Symbols.more_horiz_sharp),
                                onPressed: () => unawaited(_showMenu(anchor: anchor)),
                              ),
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

/// A card's title in up to two lines, broken only between words: a word
/// wider than the line (narrow covers in a short window) ends in an
/// ellipsis on one line rather than splitting ("Whitebo / ard").
class _CardTitle extends StatelessWidget {
  const _CardTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge;
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        );
        final splits = title.split(' ').any((word) {
          painter
            ..text = TextSpan(text: word, style: style)
            ..layout();
          return painter.width > constraints.maxWidth;
        });
        painter.dispose();
        return Text(title, style: style, maxLines: splits ? 1 : 2, overflow: TextOverflow.ellipsis);
      },
    );
  }
}
