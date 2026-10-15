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
import 'page_commands.dart';
import 'page_moves.dart';

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
    Widget thumb({bool target = false}) => _Thumb(
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

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.tile,
    required this.hovered,
    required this.dropTarget,
    required this.onHover,
  });

  final PageTile tile;
  final bool hovered;
  final bool dropTarget;
  final ValueChanged<bool> onHover;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Only selection rings the page (blue marks state); the page on screen
    // is marked by the margin rule beside its number (_Footer).
    final ring = tile.selecting && tile.selected;
    return Center(
      child: GestureDetector(
        onTap: tile.onTap,
        onLongPress: tile.reorderable && !tile.selecting ? null : tile.onLongPress,
        onSecondaryTap: tile.selecting ? null : tile.onLongPress,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => onHover(true),
          onExit: (_) => onHover(false),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Paper at rest: square corners, the contact shadow only
              // (DESIGN §3); hover is the ink overlay on the page.
              AnimatedContainer(
                duration: Motion.fast,
                padding: const EdgeInsets.all(Hairline.rule + Gaps.xxs),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.xs),
                  border: Border.all(
                    color: ring ? scheme.primary : Colors.transparent,
                    width: Hairline.rule,
                  ),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(boxShadow: Shadows.low(theme.brightness)),
                  position: DecorationPosition.background,
                  child: Stack(
                    fit: StackFit.passthrough,
                    children: [
                      PageThumbnail(
                        page: tile.page,
                        cache: tile.cache,
                        backgrounds: tile.backgrounds,
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: AnimatedContainer(
                            duration: Motion.fast,
                            color: hovered && !tile.selecting
                                ? Surfaces.hovered(scheme)
                                : Colors.transparent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (tile.page.bookmarked)
                Positioned(
                  top: 0,
                  right: 14,
                  child: Icon(Symbols.bookmark_sharp, fill: 1, size: 26, color: Palette.bookmark),
                ),
              if (tile.selecting)
                Positioned(top: 10, left: 10, child: _Check(selected: tile.selected)),
              // Where a dragged page will land: a margin rule before this one.
              if (dropTarget)
                Positioned(
                  left: -Gaps.md,
                  top: 0,
                  bottom: 0,
                  child: Container(width: Hairline.rule, color: scheme.primary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: Motion.fast,
      width: 24,
      height: 24,
      // A checkbox (DESIGN §6): 2-dp corners, blue when on; flat on paper.
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.xs),
        color: selected ? scheme.primary : Colors.white.withValues(alpha: 0.9),
        border: Border.all(color: selected ? scheme.primary : Colors.black54, width: 1.5),
      ),
      child: selected
          ? Icon(Symbols.check_sharp, size: Glyphs.menu, color: scheme.onPrimary)
          : null,
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
      height: 40,
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
