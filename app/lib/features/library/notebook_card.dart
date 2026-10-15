import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../domain/notebook.dart';
import '../../ui/app_theme.dart';
import '../../ui/context_menu_keys.dart';
import '../../ui/end_keeping_text.dart';
import 'cover_locator.dart';
import 'library_actions.dart';
import 'library_drag.dart';
import 'library_draggable.dart';
import 'library_menus.dart';
import 'notebook_cover.dart';
import 'selection/selection_mark.dart';

part 'notebook_card_caption.dart';

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
    this.recordings = 0,
  });

  final Notebook notebook;
  final String subtitle;

  /// How many audio recordings it has: a mic glyph leads the caption.
  final int recordings;
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
    final recordings = widget.recordings;
    // For screen readers the card is a button named by its title and
    // caption (the cover takes taps and long presses), the ⋯ a button
    // beside it: whether or not the ⋯ shows, the card stays a button.
    // Tab reaches the ⋯ right after its card.
    return FocusTraversalGroup(
      child: Semantics(
        container: true,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Semantics(
                  container: true,
                  button: true,
                  selected: _selecting ? _selected : null,
                  label: [
                    _notebook.title,
                    if (recordings > 0) recordings == 1 ? '1 recording' : '$recordings recordings',
                    widget.subtitle,
                  ].join('\n'),
                  child: LibraryDraggable(
                    item: LibraryDragItem.notebook(_notebook.id),
                    feedback: DragFeedback(
                      width: 110,
                      height: 110 / 0.72,
                      child: NotebookCover.of(_notebook),
                    ),
                    onLongPressMenu: () => unawaited(_showMenu()),
                    child: ContextMenuKeys(onMenu: () => unawaited(_showMenu()), child: cover),
                  ),
                ),
              ),
              // A fixed caption area, so every cover in a row is as tall.
              _caption(context, showMore: showMore),
            ],
          ),
        ),
      ),
    );
  }
}
