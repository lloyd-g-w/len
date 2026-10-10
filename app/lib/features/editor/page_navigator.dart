import 'package:flutter/material.dart';

import '../../ui/app_theme.dart';
import '../../ui/floating_panel.dart';
import 'chrome/canvas_guard.dart';

/// "‹ 3 / 12 › ＋▾" for paged notebooks: page turning, the current page
/// (tap to jump to a page) and adding pages.
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
    this.compact = false,
  });

  /// Phones: just the page number between "all pages" and "add page"
  /// (pages are turned by scrolling or swiping).
  final bool compact;

  final int index;
  final int count;
  final ValueChanged<int> onSelect;

  /// Adds a page like the current one after it.
  final VoidCallback onAddPage;

  /// Shows all pages (on phones, where the top bar has no room for it).
  final VoidCallback? onOverview;
  final VoidCallback? onGoTo;
  final VoidCallback? onAddWithTemplate;
  final VoidCallback? onInsertPdf;

  /// Whether the current page is bookmarked (shown next to the number).
  final bool bookmarked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget button(String tooltip, IconData icon, VoidCallback? onPressed) => IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: 22,
      style: IconButton.styleFrom(
        foregroundColor: scheme.onSurfaceVariant,
        fixedSize: const Size(40, 40),
        minimumSize: const Size(40, 40),
        padding: EdgeInsets.zero,
      ),
      icon: Icon(icon),
    );
    return FloatingPanel(
      padding: const EdgeInsets.symmetric(horizontal: Gaps.xs, vertical: Gaps.xxs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onOverview != null) button('All pages', Icons.grid_view_rounded, onOverview),
          if (!compact)
            button(
              'Previous page',
              Icons.chevron_left_rounded,
              index > 0 ? () => onSelect(index - 1) : null,
            ),
          Tooltip(
            message: 'Go to page',
            child: InkWell(
              onTap: onGoTo,
              borderRadius: BorderRadius.circular(Radii.sm),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gaps.xs, vertical: Gaps.sm),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (bookmarked)
                      Padding(
                        padding: const EdgeInsets.only(right: Gaps.xxs),
                        child: Icon(Icons.bookmark_rounded, size: 16, color: scheme.tertiary),
                      ),
                    Text(
                      '${index + 1} / $count',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!compact) ...[
            button(
              'Next page',
              Icons.chevron_right_rounded,
              index < count - 1 ? () => onSelect(index + 1) : null,
            ),
            Container(
              width: 1,
              height: 20,
              margin: const EdgeInsets.symmetric(horizontal: Gaps.xs),
              color: scheme.outlineVariant,
            ),
          ],
          button('Add page after this one', Icons.add_rounded, onAddPage),
          if (!compact && (onAddWithTemplate != null || onInsertPdf != null))
            _moreAdd(context, scheme),
        ],
      ),
    );
  }

  Widget _moreAdd(BuildContext context, ColorScheme scheme) => ChromeMenuAnchor(
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
      style: IconButton.styleFrom(
        foregroundColor: scheme.onSurfaceVariant,
        fixedSize: const Size(28, 40),
        minimumSize: const Size(28, 40),
        padding: EdgeInsets.zero,
      ),
      onPressed: () => menu.isOpen ? menu.close() : menu.open(),
      icon: const Icon(Icons.expand_more_rounded, size: 20),
    ),
  );
}
