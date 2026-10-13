import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/notebook_page.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/menus.dart';
import '../../editor/document/page_backgrounds.dart';
import '../../editor/document/page_thumbnail.dart';
import 'page_commands.dart';

/// One page in the overview: a live thumbnail with its number, bookmark
/// ribbon, current-page ring, selection check and options menu. Long-press
/// and drag to reorder (when [reorderable]); a bar shows where it lands.
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
  });

  final int index;
  final NotebookPage page;
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

  @override
  State<PageTile> createState() => _PageTileState();
}

class _PageTileState extends State<PageTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final label =
        'Page ${w.index + 1}${w.page.bookmarked ? ', bookmarked' : ''}'
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
    return Semantics(
      label: label,
      button: true,
      selected: w.selecting && w.selected,
      child: Column(
        children: [
          Expanded(child: body),
          const SizedBox(height: Gaps.xs),
          _Footer(tile: w),
        ],
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
    final ring = tile.selecting ? tile.selected : tile.current;
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
              AnimatedContainer(
                duration: Motion.fast,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.sm),
                  border: Border.all(color: ring ? scheme.primary : Colors.transparent, width: 2.5),
                ),
                child: AnimatedContainer(
                  duration: Motion.fast,
                  transform: Matrix4.translationValues(0, hovered && !tile.selecting ? -2 : 0, 0),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Radii.sm),
                    boxShadow: hovered
                        ? Shadows.high(theme.brightness)
                        : Shadows.low(theme.brightness),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.sm),
                    child: PageThumbnail(
                      page: tile.page,
                      cache: tile.cache,
                      backgrounds: tile.backgrounds,
                    ),
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
              // Where a dragged page will land: before this one.
              if (dropTarget)
                Positioned(
                  left: -Gaps.md,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                  ),
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
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? scheme.primary : Colors.white.withValues(alpha: 0.9),
        border: Border.all(color: selected ? scheme.primary : scheme.outline, width: 1.5),
        boxShadow: Shadows.low(Brightness.light),
      ),
      child: selected
          ? Icon(Symbols.check_sharp, size: Glyphs.menu, color: scheme.onPrimary)
          : null,
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.tile});

  final PageTile tile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final number = Container(
      padding: const EdgeInsets.symmetric(horizontal: Gaps.sm, vertical: Gaps.xxs),
      decoration: BoxDecoration(
        // The neutral plate: blue marks the selection, not the page on screen.
        color: tile.current ? Surfaces.pressed(scheme) : Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        '${tile.index + 1}',
        style: theme.textTheme.labelLarge?.copyWith(
          color: tile.current ? scheme.onSurface : scheme.onSurfaceVariant,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
    return SizedBox(
      height: 40,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          number,
          if (!tile.selecting)
            Positioned(
              right: 0,
              child: MenuIconButton<PageCommand>(
                tooltip: 'Page ${tile.index + 1} options',
                icon: Icon(
                  Symbols.more_horiz_sharp,
                  size: Glyphs.bar,
                  color: scheme.onSurfaceVariant,
                ),
                onSelected: tile.onCommand,
                items: () => pageMenuItems(tile.page),
              ),
            ),
        ],
      ),
    );
  }
}

class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: -0.03,
    child: SizedBox(
      width: 132,
      child: Material(type: MaterialType.transparency, child: child),
    ),
  );
}
