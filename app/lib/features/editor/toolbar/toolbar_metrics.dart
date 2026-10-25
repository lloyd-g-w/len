import 'package:flutter/widgets.dart';

import '../../../ink/tool_settings.dart';
import '../../../ui/app_theme.dart';
import '../chrome/bar_button.dart';
import '../chrome/chrome_metrics.dart';
import 'tool_switcher.dart';

/// Sizes of the toolbar's parts, so the chrome can decide (before laying
/// anything out) whether the tools fit inside the top bar on one row, and
/// how much room the sub-bar under them takes.
///
/// Cells are wider on touch-first devices (48-dp tool and 44-dp slot hit
/// areas, [Targets]); visuals stay 40 and 36. Inside a [ToolbarDensity]
/// marked compact (a tool row short of room, e.g. a split pane) cells
/// shrink to the visuals.
abstract final class ToolbarMetrics {
  /// One tool button's cell: the 40-dp visual plus the 4-dp gap, or the
  /// 48-dp touch target.
  static double get tool => Targets.touchFirst ? Targets.touch : Targets.bar + Gaps.xs;

  /// A top-bar button's cell ([BarButton]).
  static double get barButton => Targets.touchFirst ? Targets.touch : Targets.bar;

  /// One quick slot's cell.
  static double get slot => Targets.touchFirst ? Targets.slotTouch : Targets.slot;

  /// A tool cell, [compact] or not.
  static double toolCell({bool compact = false}) => compact ? Targets.bar : tool;

  /// A slot cell, [compact] or not.
  static double slotCell({bool compact = false}) => compact ? Targets.slot : slot;

  /// The slot cell where [context] is.
  static double slotOf(BuildContext context) =>
      slotCell(compact: ToolbarDensity.compactOf(context));

  /// The tool cell where [context] is.
  static double toolOf(BuildContext context) =>
      toolCell(compact: ToolbarDensity.compactOf(context));

  /// A cluster divider: 1 px with 6 on each side (clusters sit 12 apart).
  static const double divider = 13;

  /// Height of the tool row attached under the top bar.
  static const double rowHeight = 48;

  /// Height of the phone's bottom tool row (without the gesture inset).
  static const double bottomHeight = 56;

  /// Width of the tool cluster: every tool plus Insert ⊕. The main bar
  /// holds the tools alone (the active tool's quick controls are in its
  /// sub-bar), so its width never changes with the tool or the slots.
  static double cluster({bool compact = false}) =>
      (EditorTool.values.length + 1) * toolCell(compact: compact);

  /// The switcher and the previous tool: what a short window's bar
  /// carries ([ToolbarDock.slim]).
  static double get slim => ToolSwitcherButton.width + PreviousToolButton.width;

  /// The sub-bar's padding around its controls, across the bar.
  static const double subBarPadding = Gaps.xs;

  /// The sub-bar's padding at its rounded ends.
  static const double subBarEnd = Gaps.sm;

  /// Height of the sub-bar (the active tool's quick controls): a slot
  /// cell and its padding.
  static double get subBarHeight => slot + 2 * subBarPadding;

  /// The gap between the main bar and its sub-bar.
  static const double subBarGap = Gaps.sm;

  /// The room the sub-bar takes beside the main bar's edge: the gap and
  /// the sub-bar.
  static double get subBarBand => subBarGap + subBarHeight;

  /// The narrowest the title may get before the bar becomes two rows.
  static const double minTitle = 120;

  /// The bar's navigation cluster at its narrowest: back, pages, title.
  static double nav({required bool paged}) => (paged ? 2 : 1) * barButton + minTitle + Gaps.xs;

  /// The bar's action cluster while idle: audio (🎙▾), undo, redo, ⋯.
  static double get actions => 4 * barButton + 20;

  /// Width of the top bar with the tools inside it (one row).
  static double oneRow({required bool paged}) =>
      nav(paged: paged) + divider + cluster() + divider + actions + 2 * Gaps.xs;

  /// Whether a pane [width] wide shows the tools inside the top bar.
  static bool fitsOneRow(double width, {required bool paged}) =>
      width >= ChromeMetrics.compactWidth && oneRow(paged: paged) <= width;
}

/// Marks a toolbar laid out with compact cells (40-dp tools, 36-dp slots)
/// because its row is short of room.
class ToolbarDensity extends InheritedWidget {
  const ToolbarDensity({super.key, required this.compact, required super.child});

  final bool compact;

  /// Whether the toolbar at [context] is compact.
  static bool compactOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ToolbarDensity>()?.compact ?? false;

  @override
  bool updateShouldNotify(ToolbarDensity oldWidget) => oldWidget.compact != compact;
}

/// The direction a toolbar runs: across (docked, floating) or down (a
/// floating palette snapped to the left or right edge). Its cluster,
/// strips and slots lay out along it.
class ToolbarAxis extends InheritedWidget {
  const ToolbarAxis({super.key, required this.axis, required super.child});

  final Axis axis;

  /// The axis of the toolbar at [context] (horizontal outside one).
  static Axis of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ToolbarAxis>()?.axis ?? Axis.horizontal;

  /// A [gap] along the toolbar at [context].
  static Widget gap(BuildContext context, double gap) =>
      of(context) == Axis.horizontal ? SizedBox(width: gap) : SizedBox(height: gap);

  @override
  bool updateShouldNotify(ToolbarAxis oldWidget) => oldWidget.axis != axis;
}
