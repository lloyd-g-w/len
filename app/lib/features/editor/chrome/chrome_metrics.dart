import '../../../ui/app_theme.dart';

/// Sizes shared by the editor chrome (top bar, tabs, toolbar, page
/// navigator), so the canvas can keep content clear of it. Widths are the
/// editor pane's, not the window's (split view).
abstract final class ChromeMetrics {
  /// Height of the top bar's button row.
  static const double barHeight = 52;

  /// Height of the tab strip shown above it when several notebooks are open.
  static const double tabHeight = 40;

  /// Room taken by the page navigator at the bottom.
  static const double navigatorExtent = 60;

  /// Margin between floating chrome and the screen edges.
  static const double edge = Gaps.md;

  /// Below this width the editor is laid out for phones: a slim top bar
  /// (back, title, undo, redo, ⋯) and the tools in a bottom row.
  static const double compactWidth = 600;

  /// From this width the tab strip replaces the phone tab switcher.
  static const double tabStripWidth = compactWidth;
}
