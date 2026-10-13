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
import 'title_button.dart';
import 'undo_redo_buttons.dart';

/// The editor's top bar, in fixed clusters: navigation (back, ▦ pages,
/// the title with its folder; tap it to rename) · the tools, when docked
/// inside the bar · actions (🎙▾ audio, undo, redo, ⋯). With the tools
/// docked as a row, that row is attached under the bar (one hairline under
/// the block). Phones keep back, the title, undo, redo and ⋯. Several open
/// notebooks add a tab strip above it (tablets, desktops).
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
    this.band = false,
  });

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

  /// An empty strip-coloured band in place of the tab strip: the second
  /// pane's bar beside a first pane that shows the strip, so both line up.
  final bool band;

  /// Height of the bar (without the status bar and the tool row) for a
  /// given [width] (with the empty [band] in place of the strip).
  static double heightFor(double width, OpenNotebooks? tabs, {bool band = false}) =>
      ChromeMetrics.barHeight + (band || showsStrip(width, tabs) ? ChromeMetrics.tabHeight : 0);

  /// Whether a bar [width] wide shows the tab strip for [tabs].
  static bool showsStrip(double width, OpenNotebooks? tabs) =>
      tabs != null && tabs.length > 1 && width >= ChromeMetrics.tabStripWidth;

  /// Room the action cluster may take while recording (the time pill).
  static const double _recordingExtra = 150;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final strip = showsStrip(width, tabs);
        final phone = width < ChromeMetrics.compactWidth;
        final row = dock == ToolbarDock.row && !phone ? toolbar : null;
        // With tabs, the status bar area takes the strip's colour.
        return Material(
          color: strip || band
              ? Surfaces.canvasBackdrop(scheme.brightness)
              : Surfaces.chrome(scheme),
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
                      splitAvailable: splitMenu != null,
                    ),
                  )
                else if (band)
                  const SizedBox(height: ChromeMetrics.tabHeight),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Surfaces.chrome(scheme),
                    border: Border(bottom: Surfaces.chromeEdge(scheme)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: ChromeMetrics.barHeight,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: Gaps.xs),
                          child: phone ? _phone() : _wide(width, showTitle: !strip),
                        ),
                      ),
                      ?row,
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

  Widget _back() => secondPane
      ? BarButton(
          tooltip: 'Close this pane',
          icon: Symbols.close_rounded,
          onPressed: actions.onBack,
        )
      : BarButton(tooltip: 'Back', icon: Symbols.arrow_back_rounded, onPressed: actions.onBack);

  Widget _title() => TitleButton(title: title, subtitle: subtitle, onRename: actions.onRename);

  /// ← ▦ and the title (it truncates first).
  List<Widget> _nav({required bool showTitle}) => [
    _back(),
    if (actions.onOverview case final onOverview?)
      BarButton(tooltip: 'All pages', icon: Symbols.grid_view_rounded, onPressed: onOverview),
    Flexible(
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: showTitle ? _title() : const SizedBox.shrink(),
      ),
    ),
  ];

  Widget _actions({required bool compact}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (!compact) ?audio,
      UndoRedoButtons(target: undo, redoOnlyWhenAvailable: compact),
      EditorMoreMenu(
        actions: actions,
        compact: compact,
        compactItems: compact ? compactMenuItems : const [],
        tabs: compact && tabs != null && tabs!.length > 1 ? tabs : null,
        split: compact ? null : splitMenu,
      ),
    ],
  );

  /// Tablets and desktops. With the tools inside the bar they are centred
  /// when the clusters beside them have room, else packed after the title.
  Widget _wide(double width, {required bool showTitle}) {
    final toolbar = this.toolbar;
    if (dock != ToolbarDock.inline || toolbar == null) {
      return Row(
        children: [
          Expanded(
            child: Row(children: _nav(showTitle: showTitle)),
          ),
          _actions(compact: false),
        ],
      );
    }
    final inline = SizedBox(height: ToolCluster.height, child: toolbar);
    const divider = ToolbarDivider();
    final side = (width - toolbarWidth) / 2 - ToolbarMetrics.divider - Gaps.xs;
    final nav = ToolbarMetrics.nav(paged: actions.onOverview != null);
    if (side >= nav && side >= ToolbarMetrics.actions + _recordingExtra) {
      return Row(
        children: [
          Expanded(
            child: Row(children: _nav(showTitle: showTitle)),
          ),
          divider,
          inline,
          divider,
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: _actions(compact: false),
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: Row(children: _nav(showTitle: showTitle)),
        ),
        divider,
        inline,
        divider,
        _actions(compact: false),
      ],
    );
  }

  /// ← ▦ title ↶ (↷) ⋯ (↷ only after an undo; ▦ for paged notebooks: the page overview, whose
  /// filters hold bookmarks and the outline).
  Widget _phone() => Row(
    children: [
      _back(),
      if (actions.onOverview case final onOverview?)
        BarButton(tooltip: 'All pages', icon: Symbols.grid_view_rounded, onPressed: onOverview),
      Expanded(
        child: Align(alignment: AlignmentDirectional.centerStart, child: _title()),
      ),
      _actions(compact: true),
    ],
  );
}
