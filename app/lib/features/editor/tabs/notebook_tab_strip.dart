import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/notebook.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/menus.dart';
import 'open_notebooks.dart';

/// GoodNotes-style strip of open notebooks (tablets and desktops): tap a
/// tab to switch, × (or a middle click) to close it; right click or long
/// press for its menu (open in split view, close).
class NotebookTabStrip extends StatelessWidget {
  const NotebookTabStrip({
    super.key,
    required this.tabs,
    this.onRename,
    this.splitAvailable = false,
  });

  final OpenNotebooks tabs;

  /// Double-tapping the active tab renames its notebook.
  final VoidCallback? onRename;

  /// Whether tabs offer "Open in split view" (large screens).
  final bool splitAvailable;

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
                onMenu: (context, at) => _menu(context, tab, at),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _menu(BuildContext context, OpenTab tab, Offset? at) async {
    final split = splitAvailable && tab.id != tabs.splitId;
    final choice = await showContextMenuAt<_TabAction>(
      context,
      at: at,
      items: [
        if (split)
          const MenuRow(
            value: _TabAction.split,
            icon: Symbols.vertical_split_rounded,
            label: 'Open in split view',
          ),
        const MenuRow(value: _TabAction.close, icon: Symbols.close_rounded, label: 'Close tab'),
      ],
    );
    switch (choice) {
      case _TabAction.split:
        tabs.openSplit(tab.id);
      case _TabAction.close:
        tabs.close(tab.id);
      case null:
        break;
    }
  }
}

enum _TabAction { split, close }

class _Tab extends StatelessWidget {
  const _Tab({
    super.key,
    required this.tab,
    required this.active,
    required this.onTap,
    required this.onClose,
    required this.onMenu,
    this.onRename,
  });

  final OpenTab tab;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final VoidCallback? onRename;

  /// Opens the tab's menu at a global position (or under the tab).
  final void Function(BuildContext context, Offset? at) onMenu;

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
            onLongPress: () => onMenu(context, null),
            onSecondaryTapUp: (d) => onMenu(context, d.globalPosition),
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
                          ? Symbols.gesture_rounded
                          : Symbols.menu_book_rounded,
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
                      icon: const Icon(Symbols.close_rounded),
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
