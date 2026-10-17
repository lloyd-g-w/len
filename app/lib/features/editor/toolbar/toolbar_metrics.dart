import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../domain/stroke.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/app_theme.dart';
import '../chrome/bar_button.dart';
import '../chrome/chrome_metrics.dart';
import '../editor_tools.dart';
import 'tool_switcher.dart';

/// Sizes of the toolbar's parts, so the chrome can decide (before laying
/// anything out) whether the tools fit inside the top bar on one row.
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
      ToolbarDensity.slotOf(context) ?? slotCell(compact: ToolbarDensity.compactOf(context));

  /// The tool cell where [context] is.
  static double toolOf(BuildContext context) =>
      toolCell(compact: ToolbarDensity.compactOf(context));

  /// The gap between two groups of slots (colours, widths).
  static const double groupGap = Gaps.md;

  /// A cluster divider: 1 px with 6 on each side (clusters sit 12 apart).
  static const double divider = 13;

  /// Height of the tool row attached under the top bar.
  static const double rowHeight = 48;

  /// Height of the phone's bottom tool row (without the gesture inset).
  static const double bottomHeight = 56;

  /// Width of the tool cluster: every tool plus Insert ⊕.
  static double cluster({bool compact = false}) =>
      (EditorTool.values.length + 1) * toolCell(compact: compact);

  /// Width of the widest quick-control strip any tool shows, so the strip
  /// keeps one place (and the tools never move) as tools change.
  static double strip(ToolSettings tools, {bool compact = false}) =>
      stripAt(tools, slotCell(compact: compact));

  /// [strip] with [slot] cells.
  static double stripAt(ToolSettings tools, double slot) {
    var widest = 0.0;
    for (final d in editorTools(tools)) {
      final w = d.stripWidth?.call(slot) ?? 0;
      if (w > widest) widest = w;
    }
    return widest;
  }

  /// The widest strip of quick colours and sizes (the pen's, the
  /// highlighter's or the laser's slots): what a minimal strip needs at
  /// most.
  static double inkStrip(ToolSettings tools, {bool compact = false}) {
    final slot = slotCell(compact: compact);
    double of(int colors, int sizes) => (colors + sizes) * slot + groupGap;
    final pen = tools.configOf(InkTool.ballpoint),
        highlighter = tools.configOf(InkTool.highlighter);
    return [
      of(pen.colors.length, pen.widths.length),
      of(highlighter.colors.length, highlighter.widths.length),
      of(tools.laser.colors.length, tools.laser.sizes.length),
    ].reduce(math.max);
  }

  /// Tools, a divider and the reserved strip: the group shown in the bar,
  /// the attached row or the floating palette.
  static double group(ToolSettings tools, {bool compact = false}) =>
      cluster(compact: compact) + divider + strip(tools, compact: compact);

  /// The switcher, the previous tool, a divider and the reserved strip:
  /// the group a short window's bar carries ([ToolbarDock.slim]).
  static double slim(ToolSettings tools) =>
      ToolSwitcherButton.width + PreviousToolButton.width + divider + strip(tools);

  /// The narrowest the title may get before the bar becomes two rows.
  static const double minTitle = 120;

  /// The bar's navigation cluster at its narrowest: back, pages, title.
  static double nav({required bool paged}) => (paged ? 2 : 1) * barButton + minTitle + Gaps.xs;

  /// The bar's action cluster while idle: audio (🎙▾), undo, redo, ⋯.
  static double get actions => 4 * barButton + 20;

  /// Width of the top bar with the tools inside it (one row).
  static double oneRow(ToolSettings tools, {required bool paged}) =>
      nav(paged: paged) + divider + group(tools) + divider + actions + 2 * Gaps.xs;

  /// Whether a pane [width] wide shows the tools inside the top bar.
  static bool fitsOneRow(double width, ToolSettings tools, {required bool paged}) =>
      width >= ChromeMetrics.compactWidth && oneRow(tools, paged: paged) <= width;
}

/// Marks a toolbar laid out with compact cells (40-dp tools, 36-dp slots)
/// because its row is short of room, and a [minimal] one (the phone's
/// bottom row) that leaves out secondary controls (the shape kind button:
/// the switcher shows the kind, and its options list them).
class ToolbarDensity extends InheritedWidget {
  const ToolbarDensity({
    super.key,
    required this.compact,
    this.minimal = false,
    this.slot,
    required super.child,
  });

  final bool compact;
  final bool minimal;

  /// A slot cell between the compact and the full one, when the row fits
  /// exactly that (the phone row with its previous-tool button).
  final double? slot;

  /// The slot cell set at [context], if any.
  static double? slotOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ToolbarDensity>()?.slot;

  /// Whether the toolbar at [context] is compact.
  static bool compactOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ToolbarDensity>()?.compact ?? false;

  /// Whether the toolbar at [context] is minimal.
  static bool minimalOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ToolbarDensity>()?.minimal ?? false;

  @override
  bool updateShouldNotify(ToolbarDensity oldWidget) =>
      oldWidget.compact != compact || oldWidget.minimal != minimal || oldWidget.slot != slot;
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
