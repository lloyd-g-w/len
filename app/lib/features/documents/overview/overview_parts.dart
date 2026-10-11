import 'package:flutter/material.dart';

import '../../../domain/tag.dart';
import '../../../ui/app_dialogs.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/menus.dart';
import '../../../ui/messages.dart';
import '../../tags/tag_widgets.dart';

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
    this.tags = const [],
    this.tag,
    this.onTag,
  });

  final int pageCount;

  /// Tags on pages of the notebook; [tag] the one filtered by (id).
  final List<Tag> tags;
  final String? tag;
  final ValueChanged<String?>? onTag;
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
          avatar: Icon(
            bookmarksOnly ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
            size: 18,
          ),
          showCheckmark: false,
          label: const Text('Bookmarks'),
          selected: bookmarksOnly,
          onSelected: onBookmarksOnly,
        ),
        if (tags.isNotEmpty && onTag != null) ...[
          const SizedBox(width: Gaps.xs),
          _TagFilter(tags: tags, tag: tag, onTag: onTag!),
        ],
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
      backgroundColor: scheme.secondaryContainer,
      foregroundColor: scheme.onSecondaryContainer,
      leading: IconButton(
        tooltip: 'Done',
        icon: const Icon(Icons.close_rounded),
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
          icon: Icons.delete_outline_rounded,
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
                      Icons.bookmark_border_rounded,
                      'Bookmark',
                      () => onAction(SelectionAction.bookmark),
                    ),
                    action(
                      Icons.library_add_outlined,
                      'Duplicate',
                      () => onAction(SelectionAction.duplicate),
                    ),
                    action(
                      Icons.delete_outline_rounded,
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
                          Icon(Icons.add_rounded, size: 32, color: scheme.primary),
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

/// Filters the overview by one page tag (a chip opening a menu).
class _TagFilter extends StatelessWidget {
  const _TagFilter({required this.tags, required this.tag, required this.onTag});

  final List<Tag> tags;
  final String? tag;
  final ValueChanged<String?> onTag;

  @override
  Widget build(BuildContext context) {
    final selected = tags.where((t) => t.id == tag).firstOrNull;
    return Builder(
      builder: (anchor) => FilterChip(
        key: const ValueKey('overview-tag-filter'),
        avatar: selected == null
            ? const Icon(Icons.sell_outlined, size: 18)
            : TagDot(selected.color, size: 12),
        showCheckmark: false,
        label: Text(selected?.name ?? 'Tags'),
        selected: selected != null,
        onSelected: (_) async {
          final choice = await showContextMenuAt<String>(
            anchor,
            items: [
              MenuRow(value: '', label: 'All pages', checked: selected == null),
              const PopupMenuDivider(),
              for (final t in tags) MenuRow(value: t.id, label: t.name, checked: t.id == tag),
            ],
          );
          if (choice != null) onTag(choice.isEmpty ? null : choice);
        },
      ),
    );
  }
}

/// Shown when the bookmarks or tag filter finds nothing.
class NoBookmarks extends StatelessWidget {
  const NoBookmarks({super.key, this.tag});

  /// The tag filtered by, if any.
  final String? tag;

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
              tag == null ? Icons.bookmark_border_rounded : Icons.sell_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: Gaps.lg),
            Text(
              tag == null ? 'No bookmarked pages yet' : 'No pages tagged “$tag”',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: Gaps.xs),
            Text(
              tag == null
                  ? 'Bookmark pages from their ··· menu to find them here.'
                  : 'Tag pages from the editor’s Page menu, or clear the filters.',
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
