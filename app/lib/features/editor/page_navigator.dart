import 'package:flutter/material.dart';

import '../../ui/floating_panel.dart';

/// "▦ ‹ 3 / 12 › + ▾" control for paged notebooks: overview, page turning,
/// current page indicator (tap to jump) and adding pages.
class PageNavigator extends StatelessWidget {
  const PageNavigator({
    super.key,
    required this.index,
    required this.count,
    required this.onSelect,
    required this.onAddPage,
    this.onOverview,
    this.onGoTo,
    this.onAddWithTemplate,
    this.onInsertPdf,
    this.bookmarked = false,
  });

  final int index;
  final int count;
  final ValueChanged<int> onSelect;

  /// Adds a page like the current one after it.
  final VoidCallback onAddPage;
  final VoidCallback? onOverview;
  final VoidCallback? onGoTo;
  final VoidCallback? onAddWithTemplate;
  final VoidCallback? onInsertPdf;

  /// Whether the current page is bookmarked (shown next to the number).
  final bool bookmarked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FloatingPanel(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onOverview != null)
            IconButton(
              tooltip: 'All pages',
              onPressed: onOverview,
              icon: const Icon(Icons.grid_view_rounded),
            ),
          IconButton(
            tooltip: 'Previous page',
            onPressed: index > 0 ? () => onSelect(index - 1) : null,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Tooltip(
            message: 'Go to page',
            child: InkWell(
              onTap: onGoTo,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (bookmarked)
                      Icon(Icons.bookmark_rounded, size: 16, color: theme.colorScheme.tertiary),
                    Text('${index + 1} / $count', style: theme.textTheme.labelLarge),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Next page',
            onPressed: index < count - 1 ? () => onSelect(index + 1) : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
          IconButton(
            tooltip: 'Add page after this one',
            onPressed: onAddPage,
            icon: const Icon(Icons.note_add_outlined),
          ),
          if (onAddWithTemplate != null || onInsertPdf != null) _moreAdd(),
        ],
      ),
    );
  }

  Widget _moreAdd() => MenuAnchor(
    menuChildren: [
      if (onAddWithTemplate != null)
        MenuItemButton(
          leadingIcon: const Icon(Icons.grid_on_rounded),
          onPressed: onAddWithTemplate,
          child: const Text('Add page with template…'),
        ),
      if (onInsertPdf != null)
        MenuItemButton(
          leadingIcon: const Icon(Icons.picture_as_pdf_outlined),
          onPressed: onInsertPdf,
          child: const Text('Insert PDF pages…'),
        ),
    ],
    builder: (context, menu, _) => IconButton(
      tooltip: 'More ways to add pages',
      visualDensity: VisualDensity.compact,
      onPressed: () => menu.isOpen ? menu.close() : menu.open(),
      icon: const Icon(Icons.arrow_drop_down_rounded),
    ),
  );
}
