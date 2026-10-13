import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../../ui/app_theme.dart';
import 'thumbnails/thumbnail_renderer.dart';

/// The notebook grid's layout: covers of about [coverWidth] (at least two
/// columns, stretched to the width) at [ThumbnailRenderer.aspect], with
/// [captionHeight] below each for the title and caption. In a short
/// viewport (a phone held sideways) covers narrow, by adding columns, until
/// a cover and its caption take at most [maxRowShare] of the height, so a
/// whole row with its titles fits under the header. In a short window
/// (`Breakpoints.short`) the row may take all the height the chrome above
/// it leaves (less a margin), so covers are as large as the window allows.
class CoverGridDelegate extends SliverGridDelegate {
  const CoverGridDelegate({
    required this.coverWidth,
    required this.spacing,
    required this.captionHeight,
  });

  final double coverWidth;
  final double spacing;
  final double captionHeight;

  /// The most of the viewport's height one row (cover and caption) takes.
  static const double maxRowShare = 0.6;

  /// The narrowest a cover gets to fit [maxRowShare].
  static const double minCoverWidth = 96;

  /// How many columns of about [coverWidth] fit [width] (at least two);
  /// with a [height] (the viewport's), more if covers would be taller than
  /// [maxRowShare] of it with their [captionHeight].
  static int columnsFor(
    double width,
    double coverWidth,
    double spacing, {
    double? height,
    double captionHeight = 0,
  }) {
    final columns = math.max(2, ((width + spacing) / (coverWidth + spacing)).floor());
    if (height == null || !height.isFinite) return columns;
    final widest = (height * maxRowShare - captionHeight) * ThumbnailRenderer.aspect;
    final tile = (width - spacing * (columns - 1)) / columns;
    if (tile <= widest) return columns;
    // Never narrower than [minCoverWidth] (large text in a short window
    // would shrink covers to stamps): then the row may run under the fold.
    double tileOf(int n) => (width - spacing * (n - 1)) / n;
    var fitted = ((width + spacing) / (math.max(widest, 1) + spacing)).ceil();
    while (fitted > columns && tileOf(fitted) < minCoverWidth) {
      fitted--;
    }
    return math.max(columns, fitted);
  }

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final width = constraints.crossAxisExtent;
    final viewport = constraints.viewportMainAxisExtent;
    final columns = columnsFor(
      width,
      coverWidth,
      spacing,
      // Short: the room under the chrome, as the height whose share it is.
      height: viewport < Breakpoints.shortHeight
          ? (viewport - constraints.precedingScrollExtent - Gaps.lg) / maxRowShare
          : viewport,
      captionHeight: captionHeight,
    );
    final tile = (width - spacing * (columns - 1)) / columns;
    final height = tile / ThumbnailRenderer.aspect + captionHeight;
    return SliverGridRegularTileLayout(
      crossAxisCount: columns,
      mainAxisStride: height + Gaps.lg,
      crossAxisStride: tile + spacing,
      childMainAxisExtent: height,
      childCrossAxisExtent: tile,
      reverseCrossAxis: axisDirectionIsReversed(constraints.crossAxisDirection),
    );
  }

  @override
  bool shouldRelayout(CoverGridDelegate old) =>
      old.coverWidth != coverWidth || old.spacing != spacing || old.captionHeight != captionHeight;
}
