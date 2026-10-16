import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/notebook_page.dart';
import '../../../domain/pdf_page_numbers.dart' show PdfPageNumbers;
import '../../../ui/app_theme.dart';
import '../../../ui/context_menu_keys.dart';
import '../../../ui/menus.dart';
import '../../../ui/sidebar_item.dart' show MarginRulePainter;
import '../../editor/document/page_backgrounds.dart';
import '../../editor/document/page_thumbnail.dart';
import 'overview_grid.dart';
import 'page_commands.dart';
import 'page_moves.dart';
import 'page_tile_thumb.dart';

/// One page in the overview: a live thumbnail with its number, bookmark
/// ribbon, current-page ring, selection check and options menu. Long-press
/// and drag to reorder (when [reorderable]); a bar shows where it lands.
/// With the keyboard: a stop of its own, Enter or Space as a tap, the Menu
/// key or Shift+F10 for the options menu, Ctrl+arrows to move it ([onMove];
/// screen readers offer "Move earlier" and "Move later").
class PageTile extends StatefulWidget {
  const PageTile({
    super.key,
    required this.index,
    required this.page,
    required this.cache,
    required this.backgrounds,
    required this.current,
    required this.reorderable,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onCommand,
    required this.onDrop,
    required this.onLongPress,
    this.onMove,
    this.focusNode,
    this.pdfLabel,
  });

  final int index;
  final NotebookPage page;

  /// Its PDF page's number when that differs from its own ("Slide 23",
  /// [PdfPageNumbers.labelOf]): a quiet caption beside the number.
  final String? pdfLabel;
  final ThumbnailCache cache;
  final PageBackgrounds? backgrounds;
  final bool current;
  final bool reorderable;

  /// Selection mode: taps toggle [selected] instead of opening the page.
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<PageCommand> onCommand;

  /// A page (by index) was dropped onto this one.
  final ValueChanged<int> onDrop;

  /// Long press without dragging (starts selection mode).
  final VoidCallback onLongPress;

  /// Moves the page a step toward a side (Ctrl+arrows; left and right as
  /// on screen). Null: it can't move from the keyboard.
  final ValueChanged<AxisDirection>? onMove;

  /// The tile's own focus (the page's, so that focus can follow it).
  final FocusNode? focusNode;

  @override
  State<PageTile> createState() => _PageTileState();
}

class _PageTileState extends State<PageTile> {
  bool _hovered = false;

  /// The options menu (the ⋯'s), over the tile.
  Future<void> _menu() async {
    final command = await showContextMenuAt<PageCommand>(
      context,
      items: pageMenuItems(widget.page),
    );
    if (command != null && mounted) widget.onCommand(command);
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final label =
        'Page ${w.index + 1}${w.pdfLabel == null ? '' : ', ${w.pdfLabel}'}'
        '${w.page.bookmarked ? ', bookmarked' : ''}'
        '${w.current ? ', current page' : ''}';
    Widget thumb({bool target = false}) => PageTileThumb(
      tile: w,
      hovered: _hovered,
      dropTarget: target,
      onHover: (h) => setState(() => _hovered = h),
    );
    final body = w.reorderable && !w.selecting
        ? DragTarget<int>(
            onWillAcceptWithDetails: (d) => d.data != w.index,
            onAcceptWithDetails: (d) => w.onDrop(d.data),
            builder: (context, candidates, _) => LongPressDraggable<int>(
              data: w.index,
              delay: const Duration(milliseconds: 250),
              feedback: _DragFeedback(child: thumb()),
              childWhenDragging: Opacity(opacity: 0.25, child: thumb()),
              child: thumb(target: candidates.isNotEmpty),
            ),
          )
        : thumb();
    final move = w.onMove;
    return Semantics(
      label: label,
      button: true,
      selected: w.selecting && w.selected,
      customSemanticsActions: move == null ? null : pageMoveActions(context, move),
      // Tab reaches the ⋯ right after its page.
      child: FocusTraversalGroup(
        child: CallbackShortcuts(
          bindings: move == null ? const {} : pageMoveBindings(move),
          child: ContextMenuKeys(
            onMenu: w.selecting ? null : () => unawaited(_menu()),
            child: FocusableActionDetector(
              focusNode: w.focusNode,
              actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => w.onTap())},
              child: Column(
                children: [
                  Expanded(child: body),
                  const SizedBox(height: Gaps.xs),
                  _Footer(tile: w),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The number on the left, the current page marked by the margin rule and
/// a bold number (as the sidebar marks the current row), ⋯ on the right.
class _Footer extends StatelessWidget {
  const _Footer({required this.tile});

  final PageTile tile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final current = tile.current && !tile.selecting;
    return SizedBox(
      height: OverviewGrid.footerRow(context),
      child: Row(
        children: [
          CustomPaint(
            painter: current ? MarginRulePainter(scheme.primary) : null,
            // The number starts just inside the page's left edge.
            child: const SizedBox(width: Gaps.sm, height: 20),
          ),
          Text(
            '${tile.index + 1}',
            style: theme.textTheme.labelLarge?.copyWith(
              color: current ? scheme.onSurface : scheme.onSurfaceVariant,
              fontWeight: current ? AppTheme.currentWeight : null,
              fontFeatures: AppTheme.tabularFigures,
            ),
          ),
          Expanded(
            child: tile.pdfLabel == null
                ? const SizedBox.shrink()
                // The tile's label says it already.
                : ExcludeSemantics(
                    child: Text(
                      ' · ${tile.pdfLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFeatures: AppTheme.tabularFigures,
                      ),
                    ),
                  ),
          ),
          if (!tile.selecting)
            MenuIconButton<PageCommand>(
              tooltip: 'Page ${tile.index + 1} options',
              icon: Icon(
                Symbols.more_horiz_sharp,
                size: Glyphs.bar,
                color: scheme.onSurfaceVariant,
              ),
              onSelected: tile.onCommand,
              items: () => pageMenuItems(tile.page),
              staggered: true,
            ),
        ],
      ),
    );
  }
}

/// A page being dragged: lifted (DESIGN §3), not tilted.
class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 132,
    child: Material(type: MaterialType.transparency, child: child),
  );
}
