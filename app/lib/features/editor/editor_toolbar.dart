import 'package:flutter/material.dart';

import '../../ink/tool_settings.dart';
import '../../ui/app_theme.dart';
import '../../ui/roving_focus.dart';
import 'chrome/receding.dart';
import 'toolbar/insert_menu.dart';
import 'toolbar/tool_cluster.dart';
import 'toolbar/tool_switcher.dart';
import 'toolbar/toolbar_metrics.dart';

/// Where the toolbar is shown (REDESIGN §2.1, §2.9).
enum ToolbarDock {
  /// Inside the top bar, between the title and the actions (one row).
  inline,

  /// A 48-dp row attached under the top bar (two rows).
  row,

  /// The phone's bottom row: the tool switcher and the previous tool.
  bottom,

  /// Short windows (a phone held sideways): the phone's switcher and
  /// previous tool inside the top bar, so the chrome is one row.
  slim,

  /// A raised palette the user drags anywhere.
  floating;

  /// Whether the tools sit in or under the top bar: their sub-bar hangs
  /// under the top chrome.
  bool get underTopBar => this == inline || this == row || this == slim;
}

/// The main toolbar: the tools (fixed order) and Insert ⊕ — tools only,
/// laid out for its [dock]. The active tool's quick controls are in its
/// sub-bar (`ToolSubBar`), which the chrome attaches beside it. Its parts
/// listen to the tools themselves, so switching tools rebuilds only them
/// (never the top bar or the canvas), and nothing in it moves.
class EditorToolbar extends StatelessWidget {
  const EditorToolbar({super.key, required this.tools, required this.dock, this.insert});

  final ToolSettings tools;
  final ToolbarDock dock;

  /// What Insert ⊕ offers; null leaves it out.
  final InsertActions? insert;

  /// Keyboard: Tab stops at the chosen tool and Insert; while a toolbar
  /// control has focus, the arrows along the bar move to the previous /
  /// next control, as in any toolbar, instead of reaching the editor
  /// (where they turn pages). See [RovingGroup].
  @override
  Widget build(BuildContext context) => RovingGroup(
    axis: ToolbarAxis.of(context),
    child: switch (dock) {
      ToolbarDock.inline => _cluster(),
      ToolbarDock.row => SizedBox(
        height: ToolbarMetrics.rowHeight,
        child: LayoutBuilder(builder: _row),
      ),
      ToolbarDock.bottom => SizedBox(
        height: ToolbarMetrics.bottomHeight,
        child: Center(child: _switcher()),
      ),
      ToolbarDock.slim => SizedBox(height: ToolCluster.height, child: _switcher()),
      ToolbarDock.floating => LayoutBuilder(builder: _floating),
    },
  );

  Widget _cluster() => ToolCluster(tools: tools, insert: insert);

  double get _width => ToolCluster.widthFor(insert: insert != null);

  /// Phones and short windows: the tool switcher and the previous tool
  /// (one tap swaps them).
  Widget _switcher() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ToolSwitcherButton(tools: tools, insert: insert),
      PreviousToolButton(tools: tools),
    ],
  );

  /// The tools centred in the row; short of room (split panes on touch),
  /// the cells shrink to their visuals.
  Widget _row(BuildContext context, BoxConstraints constraints) {
    final compact = _width > constraints.maxWidth - 2 * Gaps.xs;
    return ToolbarDensity(
      compact: compact,
      child: Center(child: _cluster()),
    );
  }

  /// The palette's content (its `ToolbarSlot` draws the raised pill and
  /// the grip): the tools when they fit, else the switcher. Snapped to a
  /// side edge it runs down (scrolling if the pane is too short).
  Widget _floating(BuildContext context, BoxConstraints constraints) {
    if (ToolbarAxis.of(context) == Axis.vertical) {
      return Receding(child: SingleChildScrollView(child: _cluster()));
    }
    if (_width <= constraints.maxWidth) return Receding(child: _cluster());
    return Receding(child: _switcher());
  }
}
