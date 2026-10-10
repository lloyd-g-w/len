import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/painting.dart' show EdgeInsets;

/// How a page is zoomed when a notebook opens or jumps to a page.
enum PageFit {
  /// Fit the width, but never so large that little of the page shows
  /// (landscape tablets, desktops); whole pages in single-page flow.
  auto('Automatic'),

  /// The page's width fills the screen.
  width('Fit width'),

  /// The whole page is visible.
  page('Fit page');

  const PageFit(this.label);
  final String label;

  /// Largest zoom [auto] uses, so pages don't become huge on wide desktop
  /// windows.
  static const double maxAutoScale = 1.4;

  /// [auto] keeps at least this much of a page's height on screen
  /// (landscape tablets would otherwise show only a third of a page).
  static const double minVisibleFraction = 0.55;

  /// Screen padding around a fitted page.
  static const double padding = 16;

  static PageFit parse(String? value) =>
      values.firstWhere((f) => f.name == value, orElse: () => auto);

  /// The zoom that shows a page [width] × [height] (world units) on a
  /// [screen] whose [insets] are covered by chrome, as this fit says.
  double scale({
    required Size screen,
    required EdgeInsets insets,
    required double width,
    required double height,
  }) {
    final byWidth = (screen.width - 2 * padding) / width;
    final free = screen.height - insets.vertical - 2 * padding;
    final byPage = free > 0 ? math.min(byWidth, free / height) : byWidth;
    return switch (this) {
      PageFit.width => byWidth,
      PageFit.page => byPage,
      PageFit.auto => math.max(
        byPage,
        math.min(byWidth, math.min(maxAutoScale, free / (height * minVisibleFraction))),
      ),
    };
  }
}
