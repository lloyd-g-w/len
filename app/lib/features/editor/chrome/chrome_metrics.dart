import '../../../ui/app_theme.dart';

/// Sizes shared by the editor chrome (top bar, tabs, toolbar slot, page
/// navigator), so the canvas can keep content clear of it.
abstract final class ChromeMetrics {
  /// Height of the top bar's button row.
  static const double barHeight = 52;

  /// Height of the tab strip shown above it when several notebooks are open.
  static const double tabHeight = 40;

  /// Room taken by the pen toolbar (its panel plus the gap around it).
  static const double toolbarExtent = 64;

  /// Room taken by the page navigator at the bottom.
  static const double navigatorExtent = 60;

  /// Margin between floating chrome and the screen edges.
  static const double edge = Gaps.md;

  /// Below this width the top bar keeps only the essentials (phones).
  static const double compactWidth = 640;

  /// From this width the tab strip replaces the phone tab switcher.
  static const double tabStripWidth = 720;
}
