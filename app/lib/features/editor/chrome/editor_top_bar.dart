import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_theme.dart';
import '../document/undo_target.dart';
import '../editor_toolbar.dart';
import '../tabs/notebook_tab_strip.dart';
import '../tabs/open_notebooks.dart';
import '../toolbar/tool_cluster.dart';
import '../toolbar/toolbar_metrics.dart';
import 'bar_button.dart';
import 'chrome_metrics.dart';
import 'editor_menu_actions.dart';
import 'editor_more_menu.dart';
import 'receding.dart';
import 'title_button.dart';
import 'undo_redo_buttons.dart';

part 'editor_top_bar_rows.dart';

/// The editor's top bar, in fixed clusters: navigation (back, ▦ pages,
/// the title with its folder; tap it to rename) · the tools, when docked
/// inside the bar · actions (🎙▾ audio, undo, redo, ⋯). With the tools
/// docked as a row, that row is attached under the bar (one hairline under
/// the block). Phones keep back, the title, undo, redo and ⋯; short windows
/// (a phone held sideways) add the phone's tool switcher and quick controls
/// to that one row. Several open notebooks add a tab strip above the bar
/// (tablets, desktops), or put the bar's buttons at the strip's ends when
/// the tools have a row of their own (two rows of chrome, never three).
class EditorTopBar extends StatelessWidget {
  const EditorTopBar({
    super.key,
    required this.title,
    required this.actions,
    required this.undo,
    this.tabs,
    this.subtitle,
    this.audio,
    this.toolbar,
    this.dock = ToolbarDock.floating,
    this.toolbarWidth = 0,
    this.compactMenuItems = const [],
    this.splitMenu,
    this.secondPane = false,
    this.split = false,
    this.band = false,
    this.short = false,
    this.status,
  });

  /// Before the actions: a mark that sync is failing, if it is.
  final Widget? status;

  final String title;

  /// A quiet second line under the title (the folder).
  final String? subtitle;
  final EditorMenuActions actions;
  final UndoTarget undo;

  final OpenNotebooks? tabs;

  /// The audio split button (features/audio), first of the actions; on
  /// phones it hides and [compactMenuItems] go into the "⋯" menu instead.
  final Widget? audio;
  final List<Widget> compactMenuItems;

  /// The toolbar, shown inside the bar ([ToolbarDock.inline]) or as the
  /// attached row ([ToolbarDock.row]); other docks leave it out.
  final Widget? toolbar;
  final ToolbarDock dock;

  /// The inline toolbar's width (tools and the reserved strip).
  final double toolbarWidth;

  /// The "Split view" entries of the "⋯" menu (wide panes only).
  final Widget? splitMenu;

  /// The bar of a split view's second pane: back closes the pane, and
  /// the tab strip stays with the first pane.
  final bool secondPane;

  /// Both panes of a split view are shown: the bar names its notebook
  /// even under the tab strip (which marks both notebooks), so the two
  /// panes' bars match.
  final bool split;

  /// An empty strip-coloured band in place of the tab strip: the second
  /// pane's bar beside a first pane that shows the strip, so both line up.
  final bool band;

  /// A short window ([ChromeMetrics.short]): no tab strip (open notebooks
  /// are in ⋯, as on phones).
  final bool short;

  /// Height of the bar (without the status bar and the tool row) in a pane
  /// of [size] with the toolbar at [dock] (with the empty [band] in place
  /// of the strip; [split]: both panes of a split view shown).
  static double heightFor(
    Size size,
    OpenNotebooks? tabs, {
    required ToolbarDock dock,
    bool band = false,
    bool split = false,
  }) {
    final strip = band || showsStrip(size, tabs);
    final extra = strip && !stripHoldsBar(dock, split: split) ? ChromeMetrics.tabHeight : 0;
    return ChromeMetrics.barHeight + extra;
  }

  /// Whether a bar in a pane of [size] shows the tab strip for [tabs].
  static bool showsStrip(Size size, OpenNotebooks? tabs) =>
      _strip(size.width, tabs, short: ChromeMetrics.short(size.height));

  static bool _strip(double width, OpenNotebooks? tabs, {required bool short}) =>
      !short && tabs != null && tabs.length > 1 && width >= ChromeMetrics.tabStripWidth;

  /// Whether the tab strip takes in the bar's buttons (← ▦ at its start,
  /// 🎙 ↶ ↷ ⋯ at its end): when the tools have a row of their own, so the
  /// chrome is two rows, not three; the active tab names the notebook. A
  /// split view keeps both bars, which name each pane's notebook.
  static bool stripHoldsBar(ToolbarDock dock, {required bool split}) =>
      dock == ToolbarDock.row && !split;

  /// Room the action cluster may take while recording (the time pill).
  static const double _recordingExtra = 150;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final strip = _strip(width, tabs, short: short);
        final phone = width < ChromeMetrics.compactWidth;
        final row = dock == ToolbarDock.row && !phone ? toolbar : null;
        final holdsBar = strip && stripHoldsBar(dock, split: split);
        // The strip, the bar and the status bar area are one flat Board
        // block, with one hairline under it all.
        return Material(
          color: Surfaces.chrome(scheme),
          child: SafeArea(
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (holdsBar)
                  SizedBox(
                    height: ChromeMetrics.barHeight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Gaps.xs),
                      child: _stripBar(),
                    ),
                  )
                else if (strip)
                  SizedBox(
                    height: ChromeMetrics.tabHeight,
                    child: NotebookTabStrip(
                      tabs: tabs!,
                      onRename: actions.onRename,
                      splitAvailable: splitMenu != null,
                    ),
                  )
                else if (band)
                  const SizedBox(height: ChromeMetrics.tabHeight),
                DecoratedBox(
                  decoration: BoxDecoration(border: Border(bottom: Surfaces.chromeEdge(scheme))),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!holdsBar)
                        SizedBox(
                          height: ChromeMetrics.barHeight,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: Gaps.xs),
                            child: Receding(
                              child: phone
                                  ? _phone()
                                  : dock == ToolbarDock.slim
                                  ? _slim(width - 2 * Gaps.xs)
                                  : _wide(width, showTitle: !strip || split),
                            ),
                          ),
                        ),
                      if (row != null) Receding(child: row),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
