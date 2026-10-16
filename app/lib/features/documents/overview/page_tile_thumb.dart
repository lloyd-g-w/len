import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/select_check.dart';
import '../../editor/document/page_thumbnail.dart';
import 'page_tile.dart';

/// [PageTile]'s page: the live thumbnail, framed as paper, with its
/// bookmark ribbon, selection ring and check, and the drop marker.
class PageTileThumb extends StatelessWidget {
  const PageTileThumb({
    super.key,
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
                Positioned(top: 10, left: 10, child: SelectCheck(selected: tile.selected)),
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
