import 'package:flutter/material.dart';

import '../../ink/tool_settings.dart';
import '../../ui/app_theme.dart';
import '../../ui/floating_panel.dart';
import 'toolbar/insert_menu.dart';
import 'toolbar/tool_cluster.dart';
import 'toolbar/tool_strip.dart';
import 'toolbar/tool_switcher.dart';
import 'toolbar/toolbar_metrics.dart';

/// Where the toolbar is shown (REDESIGN §2.1, §2.9).
enum ToolbarDock {
  /// Inside the top bar, between the title and the actions (one row).
  inline,

  /// A 48-dp row attached under the top bar (two rows).
  row,

  /// The phone's bottom row: the tool switcher and the quick controls.
  bottom,

  /// A raised palette the user drags anywhere.
  floating,
}

/// The pen toolbar: the tools (fixed order) and Insert ⊕, then the active
/// tool's quick controls, laid out for its [dock]. Its parts listen to the
/// tools themselves, so switching tools rebuilds only them (never the top
/// bar or the canvas).
class EditorToolbar extends StatelessWidget {
  const EditorToolbar({super.key, required this.tools, required this.dock, this.insert});

  final ToolSettings tools;
  final ToolbarDock dock;

  /// What Insert ⊕ offers; null leaves it out.
  final InsertActions? insert;

  @override
  Widget build(BuildContext context) => switch (dock) {
    ToolbarDock.inline => _group(reserve: ToolbarMetrics.strip(tools)),
    ToolbarDock.row => SizedBox(
      height: ToolbarMetrics.rowHeight,
      child: LayoutBuilder(builder: _row),
    ),
    ToolbarDock.bottom => _bottom(context),
    ToolbarDock.floating => LayoutBuilder(builder: _floating),
  };

  Widget _cluster() => ToolCluster(tools: tools, insert: insert);

  /// Tools, a divider, then the strip in a [reserve]d width.
  Widget _group({required double? reserve}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _cluster(),
      const ToolbarDivider(),
      ToolStrip(tools: tools, reserve: reserve),
    ],
  );

  /// The tools centred in the row and the strip after them; when the strip
  /// has no room beside centred tools, the group (with the strip's widest
  /// width reserved) is centred instead. Either way nothing moves as the
  /// tool changes. Short of room (split panes on touch), the cells shrink
  /// to their visuals; shorter still, the strip scrolls.
  Widget _row(BuildContext context, BoxConstraints constraints) {
    final width = constraints.maxWidth - 2 * Gaps.xs;
    if (ToolbarMetrics.group(tools) <= width) return _rowOf(constraints, compact: false);
    final compact = ToolbarMetrics.group(tools, compact: true) <= width
        ? _rowOf(constraints, compact: true)
        : Row(
            children: [
              const SizedBox(width: Gaps.xs),
              _cluster(),
              const ToolbarDivider(),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ToolStrip(tools: tools),
                ),
              ),
            ],
          );
    return ToolbarDensity(compact: true, child: compact);
  }

  Widget _rowOf(BoxConstraints constraints, {required bool compact}) {
    final cluster = ToolCluster.widthFor(insert: insert != null, compact: compact);
    final reserve = ToolbarMetrics.strip(tools, compact: compact);
    final side = (constraints.maxWidth - cluster) / 2;
    if (side >= ToolbarMetrics.divider + reserve) {
      return Row(
        children: [
          const Spacer(),
          _cluster(),
          Expanded(
            child: Row(
              children: [
                const ToolbarDivider(),
                ToolStrip(tools: tools),
              ],
            ),
          ),
        ],
      );
    }
    return Center(child: _group(reserve: reserve));
  }

  /// Phones: the tool switcher, then the quick controls (scrolling when
  /// six colours and six widths don't fit).
  Widget _bottom(BuildContext context) => SizedBox(
    height: ToolbarMetrics.bottomHeight,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gaps.sm),
      child: Row(
        children: [
          ToolSwitcherButton(tools: tools, insert: insert),
          const ToolbarDivider(),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ToolStrip(tools: tools),
            ),
          ),
        ],
      ),
    ),
  );

  /// The raised palette: the full group when it fits, else the switcher
  /// and the quick controls.
  Widget _floating(BuildContext context, BoxConstraints constraints) {
    const padding = 2 * (Gaps.xs + 2);
    final reserve = ToolbarMetrics.strip(tools);
    if (ToolbarMetrics.group(tools) + padding <= constraints.maxWidth) {
      return FloatingPanel(child: _group(reserve: reserve));
    }
    return FloatingPanel(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ToolSwitcherButton(tools: tools, insert: insert),
          const ToolbarDivider(),
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ToolStrip(tools: tools),
            ),
          ),
        ],
      ),
    );
  }
}
