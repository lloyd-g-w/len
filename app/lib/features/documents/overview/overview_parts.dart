import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_dialogs.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/labelled_action.dart';
import '../../../ui/messages.dart';

/// What can be done to the pages selected in the overview.
enum SelectionAction { bookmark, duplicate, delete }

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
            child: SegmentedButton<OverviewFilter>(
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
                              size: 18,
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
    );
  }
}

/// The app bar in selection mode: count, select all, done.
class SelectionAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SelectionAppBar({
    super.key,
    required this.count,
    required this.total,
    required this.onClose,
    required this.onSelectAll,
  });

  final int count;
  final int total;
  final VoidCallback onClose;
  final VoidCallback onSelectAll;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 8);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: kToolbarHeight + 8,
      leading: IconButton(
        tooltip: 'Done',
        icon: const Icon(Symbols.close_sharp),
        onPressed: onClose,
      ),
      title: Text(count == 0 ? 'Select pages' : '$count selected'),
      actions: [
        TextButton(
          onPressed: onSelectAll,
          child: Text(count == total ? 'Select none' : 'Select all'),
        ),
        const SizedBox(width: Gaps.sm),
      ],
    );
  }
}

/// Actions for the selected pages, along the bottom (thumb reach).
class SelectionBar extends StatelessWidget {
  const SelectionBar({
    super.key,
    required this.count,
    required this.onAction,
    this.allBookmarked = false,
  });

  final int count;

  /// Whether every selected page is bookmarked: the action removes them.
  final bool allBookmarked;
  final ValueChanged<SelectionAction> onAction;

  Future<void> _delete(BuildContext context) async {
    final ok =
        count == 1 ||
        await confirmAction(
          context,
          title: 'Delete $count pages?',
          message: 'Their ink, text and images are deleted with them.',
          confirmLabel: 'Delete',
          destructive: true,
          icon: Symbols.delete_sharp,
        );
    if (ok) onAction(SelectionAction.delete);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = count > 0;
    Widget action(IconData icon, String label, VoidCallback onTap, {Color? color}) => Expanded(
      child: LabelledAction(
        icon: icon,
        label: label,
        color: color,
        onPressed: enabled ? onTap : null,
      ),
    );
    return Material(
      color: Surfaces.chrome(scheme),
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(border: Border(top: Surfaces.chromeEdge(scheme))),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gaps.md, vertical: Gaps.xs),
            child: Align(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Row(
                  children: [
                    action(
                      allBookmarked ? Symbols.bookmark_remove_sharp : Symbols.bookmark_sharp,
                      allBookmarked ? 'Remove bookmark' : 'Bookmark',
                      () => onAction(SelectionAction.bookmark),
                    ),
                    action(
                      Symbols.library_add_sharp,
                      'Duplicate',
                      () => onAction(SelectionAction.duplicate),
                    ),
                    action(
                      Symbols.delete_sharp,
                      'Delete',
                      () => _delete(context),
                      color: scheme.error,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The last tile of the overview: adds a page at the end.
class AddPageTile extends StatelessWidget {
  const AddPageTile({super.key, required this.onTap});

  final VoidCallback onTap;

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
                  child: InkWell(
                    borderRadius: BorderRadius.circular(Radii.sm),
                    onTap: onTap,
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
        const SizedBox(height: Gaps.xs + 40),
      ],
    );
  }
}

/// Shown when the bookmarks filter finds nothing.
class NoBookmarks extends StatelessWidget {
  const NoBookmarks({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gaps.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Symbols.bookmark_sharp,
              size: Glyphs.empty,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: Gaps.lg),
            Text('No bookmarked pages yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: Gaps.xs),
            Text(
              'Bookmark pages from their ··· menu to find them here',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A short message at the bottom of the screen.
void showOverviewMessage(BuildContext context, String message) {
  showMessage(context, message);
}
