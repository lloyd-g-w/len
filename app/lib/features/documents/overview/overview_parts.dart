import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_dialogs.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/messages.dart';

/// What can be done to the pages selected in the overview.
enum SelectionAction { bookmark, duplicate, delete }

/// The overview's app bar: page count, bookmarks filter, "Select".
class OverviewAppBar extends StatelessWidget implements PreferredSizeWidget {
  const OverviewAppBar({
    super.key,
    required this.pageCount,
    required this.bookmarksOnly,
    required this.compact,
    required this.onBookmarksOnly,
    required this.onSelect,
  });

  final int pageCount;

  final bool bookmarksOnly;
  final bool compact;
  final ValueChanged<bool> onBookmarksOnly;
  final VoidCallback onSelect;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 8);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppBar(
      toolbarHeight: kToolbarHeight + 8,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Pages', style: theme.textTheme.titleLarge),
          Text(pageCount == 1 ? '1 page' : '$pageCount pages', style: theme.textTheme.bodySmall),
        ],
      ),
      actions: [
        FilterChip(
          // The bookmark's colour, as on the pages and tiles.
          avatar: Icon(
            Symbols.bookmark_rounded,
            size: 18,
            fill: bookmarksOnly ? 1 : 0,
            color: bookmarksOnly ? Palette.bookmark : null,
          ),
          showCheckmark: false,
          label: const Text('Bookmarks'),
          selected: bookmarksOnly,
          onSelected: onBookmarksOnly,
        ),
        const SizedBox(width: Gaps.xs),
        TextButton(onPressed: onSelect, child: const Text('Select')),
        SizedBox(width: compact ? Gaps.xs : Gaps.md),
      ],
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
    final scheme = Theme.of(context).colorScheme;
    return AppBar(
      toolbarHeight: kToolbarHeight + 8,
      backgroundColor: scheme.surfaceContainerHigh,
      foregroundColor: scheme.onSurface,
      leading: IconButton(
        tooltip: 'Done',
        icon: const Icon(Symbols.close_rounded),
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
  const SelectionBar({super.key, required this.count, required this.onAction});

  final int count;
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
          icon: Symbols.delete_rounded,
        );
    if (ok) onAction(SelectionAction.delete);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = count > 0;
    Widget action(IconData icon, String label, VoidCallback onTap, {Color? color}) => Expanded(
      child: TextButton(
        style: TextButton.styleFrom(
          foregroundColor: color ?? scheme.onSurface,
          minimumSize: const Size(64, 56),
        ),
        onPressed: enabled ? onTap : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon),
            const SizedBox(height: Gaps.xxs),
            Text(label),
          ],
        ),
      ),
    );
    return Material(
      color: scheme.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gaps.md, vertical: Gaps.xs),
            child: Align(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Row(
                  children: [
                    action(
                      Symbols.bookmark_rounded,
                      'Bookmark',
                      () => onAction(SelectionAction.bookmark),
                    ),
                    action(
                      Symbols.library_add_rounded,
                      'Duplicate',
                      () => onAction(SelectionAction.duplicate),
                    ),
                    action(
                      Symbols.delete_rounded,
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
                padding: const EdgeInsets.all(5.5),
                child: Material(
                  color: scheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Radii.xs),
                    side: BorderSide(color: scheme.outlineVariant, width: 1.5),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(Radii.xs),
                    onTap: onTap,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Symbols.add_rounded, size: 32, color: scheme.primary),
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
            Icon(Symbols.bookmark_rounded, size: Glyphs.empty, color: theme.colorScheme.outline),
            const SizedBox(height: Gaps.lg),
            Text('No bookmarked pages yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: Gaps.xs),
            Text(
              'Bookmark pages from their ··· menu to find them here.',
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
