import 'package:flutter/material.dart';

import '../../../domain/notebook.dart';
import '../../../ui/app_theme.dart';
import 'open_notebooks.dart';

/// GoodNotes-style strip of open notebooks (tablets and desktops): tap a
/// tab to switch, × (or a middle click) to close it.
class NotebookTabStrip extends StatelessWidget {
  const NotebookTabStrip({super.key, required this.tabs, this.onRename});

  final OpenNotebooks tabs;

  /// Double-tapping the active tab renames its notebook.
  final VoidCallback? onRename;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tabs,
      builder: (context, _) => ListView(
        scrollDirection: Axis.horizontal,
        // Tabs sit on the bar below them, like browser tabs.
        padding: const EdgeInsets.only(left: Gaps.sm, right: Gaps.sm, top: Gaps.xs + 2),
        children: [
          for (final tab in tabs.tabs)
            Padding(
              padding: const EdgeInsets.only(right: Gaps.xs),
              child: _Tab(
                key: ValueKey('tab-${tab.id}'),
                tab: tab,
                active: tab.id == tabs.activeId,
                onTap: () => tabs.activate(tab.id),
                onClose: () => tabs.close(tab.id),
                onRename: tab.id == tabs.activeId ? onRename : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    super.key,
    required this.tab,
    required this.active,
    required this.onTap,
    required this.onClose,
    this.onRename,
  });

  final OpenTab tab;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final VoidCallback? onRename;

  static const BorderRadius _shape = BorderRadius.vertical(top: Radius.circular(Radii.sm));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = active ? scheme.onSurface : scheme.onSurfaceVariant;
    return Semantics(
      selected: active,
      button: true,
      label: tab.title,
      child: Listener(
        // Middle click closes, as in browsers.
        onPointerDown: (e) {
          if (e.buttons == 4) onClose();
        },
        child: Material(
          color: active ? scheme.surface : Colors.transparent,
          borderRadius: _shape,
          child: InkWell(
            onTap: onTap,
            onDoubleTap: onRename,
            borderRadius: _shape,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 112, maxWidth: 220),
              child: Padding(
                padding: const EdgeInsets.only(left: Gaps.md, right: Gaps.xxs),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      tab.kind == NotebookKind.canvas
                          ? Icons.gesture_rounded
                          : Icons.menu_book_rounded,
                      size: 16,
                      color: active ? scheme.primary : fg,
                    ),
                    const SizedBox(width: Gaps.sm),
                    Flexible(
                      child: Text(
                        tab.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: fg,
                          fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close tab',
                      onPressed: onClose,
                      iconSize: 16,
                      style: IconButton.styleFrom(
                        foregroundColor: fg,
                        minimumSize: const Size(28, 28),
                        fixedSize: const Size(28, 28),
                        padding: EdgeInsets.zero,
                      ),
                      icon: const Icon(Icons.close_rounded),
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
