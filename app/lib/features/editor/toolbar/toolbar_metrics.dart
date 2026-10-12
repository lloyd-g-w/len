import '../../../ink/tool_settings.dart';
import '../../../ui/app_theme.dart';
import '../chrome/bar_button.dart';
import '../chrome/chrome_metrics.dart';
import '../editor_tools.dart';

/// Sizes of the toolbar's parts, so the chrome can decide (before laying
/// anything out) whether the tools fit inside the top bar on one row.
///
/// Cells are wider on touch-first devices (48-dp tool and 44-dp slot hit
/// areas, [Targets]); visuals stay 40 and 36.
abstract final class ToolbarMetrics {
  /// One tool button's cell: the 40-dp visual plus the 4-dp gap, or the
  /// 48-dp touch target.
  static double get tool => Targets.touchFirst ? Targets.touch : Targets.bar + Gaps.xs;

  /// A top-bar button's cell ([BarButton]).
  static double get barButton => Targets.touchFirst ? Targets.touch : Targets.bar;

  /// One quick slot's cell.
  static double get slot => Targets.touchFirst ? Targets.slotTouch : Targets.slot;

  /// The gap between two groups of slots (colours, widths).
  static const double groupGap = Gaps.md;

  /// A cluster divider: 1 px with 6 on each side (clusters sit 12 apart).
  static const double divider = 13;

  /// Height of the tool row attached under the top bar.
  static const double rowHeight = 48;

  /// Height of the phone's bottom tool row (without the gesture inset).
  static const double bottomHeight = 56;

  /// Width of the tool cluster: every tool plus Insert ⊕.
  static double get cluster => (EditorTool.values.length + 1) * tool;

  /// Width of the widest quick-control strip any tool shows, so the strip
  /// keeps one place (and the tools never move) as tools change.
  static double strip(ToolSettings tools) {
    var widest = 0.0;
    for (final d in editorTools(tools)) {
      final w = d.stripWidth?.call() ?? 0;
      if (w > widest) widest = w;
    }
    return widest;
  }

  /// Tools, a divider and the reserved strip: the group shown in the bar,
  /// the attached row or the floating palette.
  static double group(ToolSettings tools) => cluster + divider + strip(tools);

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
