import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../domain/notebook_page.dart';
import '../../../ui/app_theme.dart';

/// The page sidebar's sizes: a slim column of fixed width, each page's
/// tile as tall as its thumbnail and number (known before it is built, so
/// the list lays out and scrolls to a page without building the pages
/// between).
abstract final class SidebarMetrics {
  /// The column's width (the system inset beside it comes on top).
  static const double width = 136;

  /// Room on both sides of a thumbnail.
  static const double side = Gaps.md;

  /// The width thumbnails are drawn at.
  static const double thumbWidth = width - 2 * side;

  /// The tallest thumbnail box, as a multiple of [thumbWidth]: a very long
  /// page shows narrower instead.
  static const double tallest = 1.6;

  /// Between tiles (above each).
  static const double gap = Gaps.sm;

  /// Whether a pane of [size] has room for the sidebar beside the page:
  /// tablets held sideways and desktops, never phones or a short window.
  static bool fits(Size size) => size.width >= Breakpoints.medium && !Breakpoints.short(size);

  /// The height of [page]'s thumbnail box.
  static double thumbHeight(NotebookPage page) {
    final aspect = page.height > 0 ? page.width / page.height : 1.0;
    return math.min(thumbWidth / aspect, thumbWidth * tallest);
  }

  /// The number row's height at the text scale of [context].
  static double labelHeight(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(20).ceilToDouble();

  /// A tile's height: the gap, the thumbnail, the number row.
  static double extent(NotebookPage page, double label) =>
      gap + thumbHeight(page) + Gaps.xs + label;
}
