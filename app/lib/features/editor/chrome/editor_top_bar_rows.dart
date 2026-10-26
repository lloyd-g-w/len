part of 'editor_top_bar.dart';

/// The bar's rows: wide (tools inline or not), under a tab strip, slim
/// (short windows) and phone; and the clusters they are made of.
extension _BarRows on EditorTopBar {
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
      ?status,
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
    if (side >= nav && side >= ToolbarMetrics.actions + EditorTopBar._recordingExtra) {
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

  /// ← ▦ and the tab strip, then the actions (see [stripHoldsBar]).
  Widget _stripBar() => Row(
    children: [
      _back(),
      if (actions.onOverview case final onOverview?)
        BarButton(tooltip: 'All pages', icon: Symbols.grid_view_rounded, onPressed: onOverview),
      Expanded(
        child: SizedBox(
          height: ChromeMetrics.tabHeight,
          child: NotebookTabStrip(
            tabs: tabs!,
            onRename: actions.onRename,
            splitAvailable: splitMenu != null,
          ),
        ),
      ),
      _actions(compact: false),
    ],
  );

  /// Short windows, one row: ← ▦ (title, when it has room), the tool
  /// switcher and quick controls, then ↶ (↷) ⋯ as on phones (audio and
  /// the open notebooks in ⋯).
  Widget _slim(double width) {
    final paged = actions.onOverview != null;
    final fixed =
        (paged ? 2 : 1) * ToolbarMetrics.barButton +
        2 * ToolbarMetrics.divider +
        3 * ToolbarMetrics.barButton;
    final room = width - fixed;
    final tools = room < toolbarWidth ? (room < 0 ? 0.0 : room) : toolbarWidth;
    const divider = ToolbarDivider();
    return Row(
      children: [
        Expanded(
          child: Row(children: _nav(showTitle: room - tools >= ToolbarMetrics.minTitle)),
        ),
        divider,
        SizedBox(width: tools, child: toolbar),
        divider,
        _actions(compact: true),
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
