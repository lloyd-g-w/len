import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ink/tool_settings.dart';
import '../../ui/app_theme.dart';
import '../../ui/floating_panel.dart';
import '../../ui/scroll_fade.dart';
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

  /// While a toolbar control has keyboard focus, ← and → move to the
  /// previous / next control (tools, Insert, then the quick slots), as in
  /// any toolbar, instead of reaching the editor (where they turn pages).
  static const Map<ShortcutActivator, Intent> arrowKeys = {
    SingleActivator(LogicalKeyboardKey.arrowLeft): DirectionalFocusIntent(TraversalDirection.left),
    SingleActivator(LogicalKeyboardKey.arrowRight): DirectionalFocusIntent(
      TraversalDirection.right,
    ),
  };

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: arrowKeys,
    child: switch (dock) {
      ToolbarDock.inline => _group(reserve: ToolbarMetrics.strip(tools)),
      ToolbarDock.row => SizedBox(
        height: ToolbarMetrics.rowHeight,
        child: LayoutBuilder(builder: _row),
      ),
      ToolbarDock.bottom => _bottom(context),
      ToolbarDock.floating => LayoutBuilder(builder: _floating),
    },
  );

  Widget _cluster() => ToolCluster(tools: tools, insert: insert);

  /// Tools, a divider, then the strip in a [reserve]d width.
  Widget _group({required double? reserve}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _cluster(),
      StripDivider(tools: tools),
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
              StripDivider(tools: tools),
              Expanded(
                child: ScrollFade(child: ToolStrip(tools: tools)),
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
                StripDivider(tools: tools),
                ToolStrip(tools: tools),
              ],
            ),
          ),
        ],
      );
    }
    return Center(child: _group(reserve: reserve));
  }

  /// Phones: the tool switcher and the previous tool (one tap swaps them),
  /// then the quick controls. The slots give up a little of their 44-dp
  /// cells for the previous tool, down to 40; short of that (narrow phones,
  /// 5 + 5 slots) it steps aside, and the slots go compact when that makes
  /// them fit, scrolling when they still don't.
  Widget _bottom(BuildContext context) => SizedBox(
    height: ToolbarMetrics.bottomHeight,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gaps.sm),
      // Slot counts decide whether the previous tool fits.
      child: LayoutBuilder(
        builder: (context, constraints) => ListenableBuilder(
          listenable: tools,
          builder: (context, _) {
            final room = constraints.maxWidth - ToolSwitcherButton.width - ToolbarMetrics.divider;
            final slot = _slotBesidePrevious(room - PreviousToolButton.width);
            final compact =
                slot == null &&
                ToolbarMetrics.inkStrip(tools) > room &&
                ToolbarMetrics.inkStrip(tools, compact: true) <= room;
            return ToolbarDensity(
              compact: compact,
              minimal: true,
              slot: slot != null && slot < ToolbarMetrics.slot ? slot : null,
              child: Row(
                children: [
                  ToolSwitcherButton(tools: tools, insert: insert),
                  if (slot != null) PreviousToolButton(tools: tools),
                  StripDivider(tools: tools),
                  Expanded(
                    child: ScrollFade(child: ToolStrip(tools: tools)),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );

  /// The largest slot cell, in whole dp from the full one down to
  /// [Targets.bar], that fits every tool's strip in [room]; null when not
  /// even that fits.
  double? _slotBesidePrevious(double room) {
    final least = math.min(Targets.bar, ToolbarMetrics.slot);
    for (var cell = ToolbarMetrics.slot; cell >= least; cell--) {
      if (ToolbarMetrics.stripAt(tools, cell) <= room) return cell;
    }
    return null;
  }

  /// The raised palette: the full group when it fits, else the switcher
  /// and the quick controls. Snapped to a side edge it runs down: the tools,
  /// then the quick slots under them (scrolling if the pane is too short).
  Widget _floating(BuildContext context, BoxConstraints constraints) {
    const padding = 2 * (Gaps.xs + 2);
    final reserve = ToolbarMetrics.strip(tools);
    if (ToolbarAxis.of(context) == Axis.vertical) {
      return FloatingPanel(
        padding: const EdgeInsets.symmetric(horizontal: Gaps.xs, vertical: Gaps.xs + 2),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: constraints.maxHeight - padding),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _cluster(),
                StripDivider(tools: tools),
                ToolStrip(tools: tools, reserve: reserve),
              ],
            ),
          ),
        ),
      );
    }
    if (ToolbarMetrics.group(tools) + padding <= constraints.maxWidth) {
      return FloatingPanel(child: _group(reserve: reserve));
    }
    return FloatingPanel(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ToolSwitcherButton(tools: tools, insert: insert),
          StripDivider(tools: tools),
          Flexible(
            child: ScrollFade(child: ToolStrip(tools: tools)),
          ),
        ],
      ),
    );
  }
}
