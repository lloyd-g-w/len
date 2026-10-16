import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/notebook.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/context_menu_keys.dart';
import '../../../ui/menus.dart';
import '../../../ui/scroll_fade.dart';
import '../../../ui/sidebar_item.dart';
import 'open_notebooks.dart';

/// GoodNotes-style strip of open notebooks (tablets and desktops): tap a
/// tab to switch, × (or a middle click) to close it; right click or long
/// press for its menu (open in split view, close). Flat on the bar's Board
/// like sidebar rows (DESIGN §6): the current tab carries the margin rule
/// and a bold Ink label, no plate. The two notebooks of a split view carry
/// a split glyph, the second a bold label without the rule.
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

  /// The widest an inactive tab grows for its title; the active tab may
  /// take [activeMaxWidth], so it is never the one cut short.
  static const double maxWidth = 220;

  /// The widest the active tab grows.
  static const double activeMaxWidth = 280;

  @override
  Widget build(BuildContext context) {
    // Tabs keep their size and the strip scrolls when they run out of
    // room, with a fade at a cut edge; the active tab scrolls into view.
    return ListenableBuilder(
      listenable: tabs,
      // Full width, so the tabs start at the leading edge.
      builder: (context, _) => SizedBox(
        width: double.infinity,
        child: ScrollFade(
          extent: Gaps.xxxl,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gaps.xs, vertical: Gaps.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final tab in tabs.tabs)
                  Padding(
                    padding: const EdgeInsets.only(right: Gaps.xs),
                    child: _Tab(
                      key: ValueKey('tab-${tab.id}'),
                      tab: tab,
                      active: tab.id == tabs.activeId,
                      split: switch (tabs.splitId) {
                        null => _Split.none,
                        final id when id == tab.id && id != tabs.activeId => _Split.second,
                        _ when tab.id == tabs.activeId => _Split.first,
                        _ => _Split.none,
                      },
                      onTap: () => tabs.activate(tab.id),
                      onClose: () => tabs.close(tab.id),
                      onRename: tab.id == tabs.activeId ? onRename : null,
                      onMenu: (context, at) => _menu(context, tab, at),
                    ),
                  ),
              ],
            ),
          ),
        ),
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
            icon: Symbols.vertical_split_sharp,
            label: 'Open in split view',
          ),
        const MenuRow(value: _TabAction.close, icon: Symbols.close_sharp, label: 'Close tab'),
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

/// A tab's part in the split view.
enum _Split { none, first, second }

class _Tab extends StatefulWidget {
  const _Tab({
    super.key,
    required this.tab,
    required this.active,
    required this.onTap,
    required this.onClose,
    required this.onMenu,
    this.split = _Split.none,
    this.onRename,
  });

  final OpenTab tab;
  final bool active;
  final _Split split;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final VoidCallback? onRename;

  /// Opens the tab's menu at a global position (or under the tab).
  final void Function(BuildContext context, Offset? at) onMenu;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  static final BorderRadius _shape = BorderRadius.circular(Radii.xs);

  @override
  void initState() {
    super.initState();
    if (widget.active) _reveal();
  }

  @override
  void didUpdateWidget(_Tab old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _reveal();
  }

  /// Scrolls this tab fully into view (only as far as needed).
  void _reveal() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    for (final policy in [
      ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    ]) {
      unawaited(Scrollable.ensureVisible(context, alignmentPolicy: policy));
    }
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final split = widget.split;
    final shown = widget.active || split == _Split.second;
    final fg = shown ? scheme.onSurface : scheme.onSurfaceVariant;
    return ContextMenuKeys(
      onMenu: () => widget.onMenu(context, null),
      child: Semantics(
        selected: widget.active,
        button: true,
        label: split == _Split.none ? widget.tab.title : '${widget.tab.title}, in split view',
        child: Listener(
          // Middle click closes, as in browsers.
          onPointerDown: (e) {
            if (e.buttons == 4) widget.onClose();
          },
          child: CustomPaint(
            foregroundPainter: widget.active ? MarginRulePainter(scheme.primary) : null,
            child: InkWell(
              onTap: widget.onTap,
              onDoubleTap: widget.onRename,
              onLongPress: () => widget.onMenu(context, null),
              onSecondaryTapUp: (d) => widget.onMenu(context, d.globalPosition),
              borderRadius: _shape,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: 112,
                  maxWidth: widget.active
                      ? NotebookTabStrip.activeMaxWidth
                      : NotebookTabStrip.maxWidth,
                ),
                child: Padding(
                  padding: const EdgeInsets.only(left: Gaps.md, right: Gaps.xxs),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        split != _Split.none
                            ? Symbols.vertical_split_sharp
                            : widget.tab.kind == NotebookKind.canvas
                            ? Symbols.gesture_sharp
                            : Symbols.menu_book_sharp,
                        size: Glyphs.menu,
                        color: fg,
                        fill: shown ? 1 : 0,
                      ),
                      const SizedBox(width: Gaps.sm),
                      Flexible(
                        child: Text(
                          widget.tab.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: fg,
                            fontWeight: shown ? AppTheme.currentWeight : null,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close tab',
                        onPressed: widget.onClose,
                        iconSize: 16,
                        style: IconButton.styleFrom(
                          foregroundColor: fg,
                          minimumSize: const Size(28, 28),
                          fixedSize: const Size(28, 28),
                          padding: EdgeInsets.zero,
                        ),
                        icon: const Icon(Symbols.close_sharp),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
