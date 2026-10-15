import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/context_menu_keys.dart';
import '../../../ui/empty_state.dart';
import '../../../ui/messages.dart';
import '../../../ui/roving_focus.dart';

export 'overview_selection.dart';

/// What the page overview shows (REDESIGN §2.4).
enum OverviewFilter {
  all('All', Symbols.grid_view_sharp),
  bookmarked('Bookmarked', Symbols.bookmark_sharp),
  outline('Outline', Symbols.toc_sharp);

  const OverviewFilter(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// The overview's app bar: page count, "Select", and the All / Bookmarked
/// / Outline filter below ([outline] false leaves Outline out).
class OverviewAppBar extends StatelessWidget implements PreferredSizeWidget {
  const OverviewAppBar({
    super.key,
    required this.pageCount,
    required this.filter,
    required this.compact,
    required this.onFilter,
    required this.onSelect,
    this.outline = true,
    this.textScale = 1,
  });

  final int pageCount;
  final OverviewFilter filter;
  final bool compact;
  final ValueChanged<OverviewFilter> onFilter;

  /// Starts selection mode; null hides "Select" (the outline has none).
  final VoidCallback? onSelect;

  /// Whether the Outline filter is offered.
  final bool outline;

  /// Height of the filter row at [textScale] (it grows with large text).
  static double filterHeight(double textScale) => 48 + 12 * (textScale - 1).clamp(0.0, 1.0);

  /// The text scale the bar is laid out for (preferredSize is asked
  /// without a context).
  final double textScale;

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight + 8 + filterHeight(textScale));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final side = compact ? Gaps.lg : Gaps.xxl;
    final back = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    return AppBar(
      toolbarHeight: kToolbarHeight + 8,
      // Without a back button the title starts where the filter and grid do.
      titleSpacing: back ? NavigationToolbar.kMiddleSpacing : side,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Pages', style: theme.textTheme.titleLarge),
          Text(pageCount == 1 ? '1 page' : '$pageCount pages', style: theme.textTheme.bodySmall),
        ],
      ),
      actions: [
        if (onSelect case final onSelect?)
          TextButton(onPressed: onSelect, child: const Text('Select')),
        SizedBox(width: compact ? Gaps.xs : Gaps.md),
      ],
      bottom: PreferredSize(
        preferredSize: Size.fromHeight(filterHeight(textScale)),
        child: Padding(
          padding: EdgeInsets.fromLTRB(side, 0, side, Gaps.sm),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: RovingSegments(
              SegmentedButton<OverviewFilter>(
                key: const ValueKey('overview-filter'),
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [
                  for (final f in OverviewFilter.values)
                    if (outline || f != OverviewFilter.outline)
                      ButtonSegment(
                        value: f,
                        // One line always: large text scales it down rather
                        // than breaking a word.
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(f.label, maxLines: 1, softWrap: false),
                        ),
                        // Phones: labels only, so three fit.
                        icon: compact
                            ? null
                            : Icon(
                                f.icon,
                                size: Glyphs.menu,
                                fill: f == filter ? 1 : 0,
                                // The bookmark's colour, as on the pages and tiles.
                                color: f == OverviewFilter.bookmarked && f == filter
                                    ? Palette.bookmark
                                    : null,
                              ),
                      ),
                ],
                selected: {filter},
                onSelectionChanged: (s) => onFilter(s.single),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The last tile of the overview: adds a page at the end; held down (or
/// right-clicked), with a template.
class AddPageTile extends StatelessWidget {
  const AddPageTile({super.key, required this.onTap, this.onLongPress});

  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 794 / 1123,
              child: Padding(
                // Where a page tile's paper sits inside its selection ring.
                padding: const EdgeInsets.all(Hairline.rule + Gaps.xxs),
                // A secondary button the size of a page, like the library's
                // New tile: a Pencil edge, no plate, an Ink "+".
                child: Material(
                  type: MaterialType.transparency,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Radii.sm),
                    side: BorderSide(color: scheme.outline),
                  ),
                  child: ContextMenuKeys(
                    onMenu: onLongPress,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(Radii.sm),
                      onTap: onTap,
                      onLongPress: onLongPress,
                      onSecondaryTap: onLongPress,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Symbols.add_sharp, size: Glyphs.empty, color: scheme.onSurface),
                            const SizedBox(height: Gaps.xs),
                            Text('Add page', style: theme.textTheme.labelLarge),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: Gaps.xs + 40),
      ],
    );
  }
}

/// Shown when the bookmarks filter finds nothing: how to bookmark, and
/// "Bookmark page N" for the page on screen ([page], 0-based), as the
/// Outline offers "Add page N to outline" (UX_AUDIT R14-3).
class NoBookmarks extends StatelessWidget {
  const NoBookmarks({super.key, this.page, this.onBookmark});

  final int? page;
  final VoidCallback? onBookmark;

  @override
  Widget build(BuildContext context) {
    final page = this.page;
    return EmptyState(
      art: const EmptyGlyph(Symbols.bookmark_sharp),
      title: 'No bookmarked pages yet',
      message: 'Bookmark pages from their ··· menu to find them here',
      action: page == null || onBookmark == null
          ? null
          : TextButton.icon(
              onPressed: onBookmark,
              icon: const Icon(Symbols.bookmark_add_sharp),
              label: Text('Bookmark page ${page + 1}'),
            ),
    );
  }
}

/// A short message at the bottom of the screen.
void showOverviewMessage(BuildContext context, String message) {
  showMessage(context, message);
}
