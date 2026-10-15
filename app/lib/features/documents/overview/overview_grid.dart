import 'package:flutter/material.dart';

import '../../../ui/app_theme.dart';
import 'page_moves.dart';

/// The overview's grid of [count] tiles, built by [tile] with the number
/// of columns it lays out (what Ctrl+↑ / ↓ move a page by).
class OverviewGrid extends StatelessWidget {
  const OverviewGrid({
    super.key,
    this.controller,
    required this.count,
    required this.compact,
    required this.tile,
  });

  /// The grid's scroll controller, if the owner follows its scrolling.
  final ScrollController? controller;

  final int count;

  /// Phones: narrower tiles and margins.
  final bool compact;
  final Widget Function(BuildContext context, int i, int columns) tile;

  @override
  Widget build(BuildContext context) {
    final side = compact ? Gaps.lg : Gaps.xxl;
    final delegate = SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: compact ? 180 : 200,
      mainAxisSpacing: Gaps.lg,
      crossAxisSpacing: compact ? Gaps.lg : Gaps.xl,
      childAspectRatio: 0.62,
    );
    return LayoutBuilder(
      builder: (context, box) {
        final columns = gridColumns(delegate, box.maxWidth - 2 * side);
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
