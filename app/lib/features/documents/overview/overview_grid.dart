import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/notebook_page.dart';
import '../../../ui/app_theme.dart';
import 'page_moves.dart';

/// A4 portrait's width / height: the overview's shape without pages.
const double a4Aspect = 794 / 1123;

/// The width / height of most of [pages] (to a hundredth), so that a slide
/// deck's overview has landscape cells (UX_AUDIT R18-3); A4 without pages.
double commonPageAspect(List<NotebookPage> pages) {
  final counts = <int, int>{};
  for (final p in pages) {
    if (p.size.height <= 0) continue;
    final key = (p.size.width / p.size.height * 100).round();
    counts[key] = (counts[key] ?? 0) + 1;
  }
  if (counts.isEmpty) return a4Aspect;
  final top = counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  return (top / 100).clamp(0.4, 2.5);
}

/// The overview's grid of [count] tiles, built by [tile] with the number
/// of columns it lays out (what Ctrl+↑ / ↓ move a page by).
class OverviewGrid extends StatelessWidget {
  const OverviewGrid({
    super.key,
    this.controller,
    required this.count,
    required this.compact,
    required this.tile,
    this.pageAspect = a4Aspect,
  });

  /// The width / height the cells are shaped for ([commonPageAspect]).
  final double pageAspect;

  /// Below a tile's page: the gap and the number row.
  static const double footer = Gaps.xs + 40;

  /// Around a tile's page: its selection ring.
  static const double ring = 2 * (Hairline.rule + Gaps.xxs);

  /// The grid's scroll controller, if the owner follows its scrolling.
  final ScrollController? controller;

  final int count;

  /// Phones: narrower tiles and margins.
  final bool compact;
  final Widget Function(BuildContext context, int i, int columns) tile;

  @override
  Widget build(BuildContext context) {
    final side = compact ? Gaps.lg : Gaps.xxl;
    final spacing = compact ? Gaps.lg : Gaps.xl;
    // Landscape pages (slides) get wider cells, so that they stay readable.
    final extent = pageAspect > 1 ? 280.0 : (compact ? 180.0 : 200.0);
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth - 2 * side;
        final probe = SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: extent,
          crossAxisSpacing: spacing,
        );
        final columns = gridColumns(probe, width);
        final cell = math.max(0.0, (width - (columns - 1) * spacing) / columns);
        final delegate = SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: extent,
          mainAxisSpacing: Gaps.lg,
          crossAxisSpacing: spacing,
          // The page's shape at the cell's width, its ring and its number.
          mainAxisExtent: math.max(0.0, cell - ring) / pageAspect + ring + footer,
        );
        return GridView.builder(
          controller: controller,
          padding: EdgeInsets.fromLTRB(
            side,
            Gaps.lg,
            side,
            Gaps.xxl + MediaQuery.paddingOf(context).bottom,
          ),
          gridDelegate: delegate,
          itemCount: count,
          itemBuilder: (context, i) => tile(context, i, columns),
        );
      },
    );
  }
}
