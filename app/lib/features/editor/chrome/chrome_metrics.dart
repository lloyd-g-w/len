import '../../../ui/app_theme.dart';

/// Sizes shared by the editor chrome (top bar, tabs, toolbar slot, page
/// navigator), so the canvas can keep content clear of it.
abstract final class ChromeMetrics {
  /// Height of the top bar's button row.
  static const double barHeight = 52;

  /// Height of the tab strip shown above it when several notebooks are open.
  static const double tabHeight = 40;

  /// Room taken by the pen toolbar (its panel plus the gap around it)
  /// until its actual height is known (see [toolbarExtentFor]).
  static const double toolbarExtent = 64;

  /// Room taken by a toolbar panel [height] high (it wraps to two rows on
  /// narrow screens): the panel, the margin to the edge and a small gap.
  static double toolbarExtentFor(double height) => height + edge + Gaps.xs;

  /// From this width the docked toolbar may sit at
  /// the top, if it fits there on one row.
  static const double topToolbarWidth = 960;

  /// Room taken by the page navigator at the bottom.
  static const double navigatorExtent = 60;

  /// Margin between floating chrome and the screen edges.
  static const double edge = Gaps.md;

  /// Below this width the top bar keeps only the essentials (phones).
  static const double compactWidth = 640;

  /// Below this the wide top bar moves All pages and the bookmark into
  /// its "⋯" menu (room for the title and a recording).
  static const double roomyBarWidth = 760;

  /// From this width the tab strip replaces the phone tab switcher.
  static const double tabStripWidth = compactWidth;
}
