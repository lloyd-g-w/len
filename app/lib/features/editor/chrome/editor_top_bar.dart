import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

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
/// every screen size), then pages and bookmark, audio, insert image, search, undo/redo, export,
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
    this.audio,
    this.compactMenuItems = const [],
    this.split,
    this.secondPane = false,
    this.band = false,
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

  /// The audio recording controls (features/audio), before insert; on
  /// phones they hide and [compactMenuItems] go into the "⋯" menu instead.
  final Widget? audio;
  final List<Widget> compactMenuItems;

  /// The split view button (large screens), before focus mode.
  final Widget? split;

  /// The bar of a split view's second pane: back closes the pane, and
  /// the tab strip stays with the first pane.
  final bool secondPane;

  /// An empty strip-coloured band in place of the tab strip: the second
  /// pane's bar beside a first pane that shows the strip, so both line up.
  final bool band;

  /// Height of the bar (without the status bar) for a given [width] (with
  /// the empty [band] in place of the strip).
  static double heightFor(double width, OpenNotebooks? tabs, {bool band = false}) =>
      ChromeMetrics.barHeight + (band || showsStrip(width, tabs) ? ChromeMetrics.tabHeight : 0);

  /// Whether a bar [width] wide shows the tab strip for [tabs].
  static bool showsStrip(double width, OpenNotebooks? tabs) =>
      tabs != null && tabs.length > 1 && width >= ChromeMetrics.tabStripWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final strip = showsStrip(width, tabs);
        // With tabs, the status bar area takes the strip's colour.
        return Material(
          color: strip || band ? scheme.surfaceContainer : scheme.surface,
          child: SafeArea(
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (strip)
                  SizedBox(
                    height: ChromeMetrics.tabHeight,
                    child: NotebookTabStrip(
                      tabs: tabs!,
                      onRename: actions.onRename,
                      splitAvailable: split != null,
                    ),
                  )
                else if (band)
                  const SizedBox(height: ChromeMetrics.tabHeight),
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
                          : _wide(width, showTitle: !strip),
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

  Widget _back() => secondPane
      ? BarButton(tooltip: 'Close this pane', icon: Symbols.close_rounded, onPressed: actions.onBack)
      : BarButton(tooltip: 'Back', icon: Symbols.arrow_back_rounded, onPressed: actions.onBack);

  Widget _title() => TitleButton(title: title, subtitle: subtitle, onRename: actions.onRename);

  /// Back and the title on the left (as on phones), page tools, history and
  /// the view and more menus on the right, in groups.
  Widget _wide(double width, {required bool showTitle}) {
    final a = actions;
    final roomy = width >= ChromeMetrics.roomyBarWidth;
    return Row(
      children: [
        _back(),
        Expanded(
          child: showTitle
              ? Align(alignment: Alignment.centerLeft, child: _title())
              : const SizedBox.shrink(),
        ),
        if (roomy && a.onOverview != null)
          BarButton(tooltip: 'All pages', icon: Symbols.grid_view_rounded, onPressed: a.onOverview),
        if (roomy && a.onToggleBookmark != null)
          BarButton(
            tooltip: a.bookmarked ? 'Remove bookmark' : 'Bookmark page',
            icon: Symbols.bookmark_rounded,
            selected: a.bookmarked,
            onPressed: a.onToggleBookmark,
          ),
        ?audio,
        ?insert,
        ?search,
        const BarDivider(),
        UndoRedoButtons(target: undo),
        const BarDivider(),
        if (a.onExport case final onExport?) ShareMenuButton(onExport: onExport),
        ?split,
        BarButton(
          tooltip: 'Focus mode (F11)',
          icon: Symbols.fullscreen_rounded,
          onPressed: a.onFocusMode,
        ),
        EditorMoreMenu(actions: a, pagesInMenu: !roomy),
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
        ?split,
        EditorMoreMenu(
          actions: actions,
          compact: true,
          compactItems: compactMenuItems,
          tabs: switcher || tabs == null || tabs.length < 2 ? null : tabs,
        ),
      ],
    );
  }
}
