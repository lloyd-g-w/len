import 'package:flutter/material.dart';

import '../../../ui/app_theme.dart';
import '../document/undo_target.dart';
import '../tabs/notebook_tab_strip.dart';
import '../tabs/open_notebooks.dart';
import '../tabs/tab_switcher.dart';
import 'bar_button.dart';
import 'chrome_metrics.dart';
import 'editor_menu_actions.dart';
import 'editor_more_menu.dart';
import 'title_button.dart';
import 'undo_redo_buttons.dart';

/// The editor's top bar: back and the notebook title on the left (on
/// every screen size), then pages and bookmark, insert image, search, undo/redo, export,
/// focus mode and more on the right. Several open notebooks add a tab strip above it
/// (tablets, desktops) or a tab switcher button (phones).
class EditorTopBar extends StatelessWidget {
  const EditorTopBar({
    super.key,
    required this.title,
    required this.actions,
    required this.undo,
    this.tabs,
    this.subtitle,
    this.search,
    this.insert,
  });

  final String title;

  /// A quiet second line under the title (e.g. the page count).
  final String? subtitle;
  final EditorMenuActions actions;
  final UndoTarget undo;
  final OpenNotebooks? tabs;

  /// The search button (features/search), before undo/redo.
  final Widget? search;

  /// The insert-image button (features/editor/images), before search.
  final Widget? insert;

  /// Height of the bar (without the status bar) for a given [width].
  static double heightFor(double width, OpenNotebooks? tabs) =>
      ChromeMetrics.barHeight + (_showStrip(width, tabs) ? ChromeMetrics.tabHeight : 0);

  static bool _showStrip(double width, OpenNotebooks? tabs) =>
      tabs != null && tabs.length > 1 && width >= ChromeMetrics.tabStripWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final strip = _showStrip(width, tabs);
        // With tabs, the status bar area takes the strip's colour.
        return Material(
          color: strip ? scheme.surfaceContainer : scheme.surface,
          child: SafeArea(
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (strip)
                  SizedBox(
                    height: ChromeMetrics.tabHeight,
                    child: NotebookTabStrip(tabs: tabs!, onRename: actions.onRename),
                  ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
                  ),
                  child: SizedBox(
                    height: ChromeMetrics.barHeight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Gaps.xs),
                      child: width < ChromeMetrics.compactWidth
                          ? _compact(width)
                          : _wide(showTitle: !strip),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _back() =>
      BarButton(tooltip: 'Back', icon: Icons.arrow_back_rounded, onPressed: actions.onBack);

  Widget _title() => TitleButton(title: title, subtitle: subtitle, onRename: actions.onRename);

  /// Back and the title on the left (as on phones), page tools, history and
  /// the view and more menus on the right, in groups.
  Widget _wide({required bool showTitle}) {
    final a = actions;
    return Row(
      children: [
        _back(),
        if (showTitle)
          Flexible(
            child: Align(alignment: Alignment.centerLeft, child: _title()),
          ),
        const Spacer(),
        if (a.onOverview != null)
          BarButton(tooltip: 'All pages', icon: Icons.grid_view_rounded, onPressed: a.onOverview),
        if (a.onToggleBookmark != null)
          BarButton(
            tooltip: a.bookmarked ? 'Remove bookmark' : 'Bookmark page',
            icon: Icons.bookmark_border_rounded,
            selectedIcon: Icons.bookmark_rounded,
            selected: a.bookmarked,
            onPressed: a.onToggleBookmark,
          ),
        ?insert,
        ?search,
        const BarDivider(),
        UndoRedoButtons(target: undo),
        const BarDivider(),
        if (a.onExport case final onExport?) ShareMenuButton(onExport: onExport),
        BarButton(
          tooltip: 'Focus mode (F11)',
          icon: Icons.fullscreen_rounded,
          onPressed: a.onFocusMode,
        ),
        EditorMoreMenu(actions: a),
      ],
    );
  }

  Widget _compact(double width) {
    final tabs = this.tabs;
    // Very narrow phones (320 dp) keep the switcher in the "⋯" menu.
    final switcher = tabs != null && tabs.length > 1 && width >= 360;
    return Row(
      children: [
        _back(),
        Expanded(
          child: Align(alignment: Alignment.centerLeft, child: _title()),
        ),
        ?insert,
        // Phones: search lives in the "⋯" menu, so the title has room.
        if (actions.onSearch == null) ?search,
        UndoRedoButtons(target: undo),
        if (switcher) TabSwitcherButton(tabs: tabs),
        EditorMoreMenu(
          actions: actions,
          compact: true,
          tabs: switcher || tabs == null || tabs.length < 2 ? null : tabs,
        ),
      ],
    );
  }
}
