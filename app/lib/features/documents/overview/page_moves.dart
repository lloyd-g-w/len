import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

/// Moving pages in the overview from the keyboard: Ctrl+← / → a place,
/// Ctrl+↑ / ↓ a row (as the scan strip moves its pages with Ctrl+arrows).

/// Where the page at [from] of [count] lands, moved a step toward
/// [direction] (as on screen; [rtl] grids run right to left) in a grid of
/// [columns]. Stops at the first and last place.
int pageStep(
  int from,
  AxisDirection direction, {
  required int columns,
  required int count,
  bool rtl = false,
}) {
  final along = rtl ? -1 : 1;
  final step = switch (direction) {
    AxisDirection.left => -along,
    AxisDirection.right => along,
    AxisDirection.up => -columns,
    AxisDirection.down => columns,
  };
  return (from + step).clamp(0, math.max(0, count - 1));
}

/// The columns [delegate] lays out across [width] (as it counts them).
int gridColumns(SliverGridDelegateWithMaxCrossAxisExtent delegate, double width) =>
    math.max(1, (width / (delegate.maxCrossAxisExtent + delegate.crossAxisSpacing)).ceil());

/// Ctrl (or ⌘) + arrows calling [move] with their direction.
Map<ShortcutActivator, VoidCallback> pageMoveBindings(ValueChanged<AxisDirection> move) => {
  for (final (key, direction) in const [
    (LogicalKeyboardKey.arrowLeft, AxisDirection.left),
    (LogicalKeyboardKey.arrowRight, AxisDirection.right),
    (LogicalKeyboardKey.arrowUp, AxisDirection.up),
    (LogicalKeyboardKey.arrowDown, AxisDirection.down),
  ]) ...{
    SingleActivator(key, control: true): () => move(direction),
    SingleActivator(key, meta: true): () => move(direction),
  },
};

/// Screen reader actions moving a page a place back or on.
Map<CustomSemanticsAction, VoidCallback> pageMoveActions(
  BuildContext context,
  ValueChanged<AxisDirection> move,
) {
  final ltr = Directionality.of(context) == TextDirection.ltr;
  return {
    const CustomSemanticsAction(label: 'Move earlier'): () =>
        move(ltr ? AxisDirection.left : AxisDirection.right),
    const CustomSemanticsAction(label: 'Move later'): () =>
        move(ltr ? AxisDirection.right : AxisDirection.left),
  };
}

/// Tells screen readers that the page at [from] went to [to] (indices).
void announcePageMove(BuildContext context, int from, int to) => SemanticsService.sendAnnouncement(
  View.of(context),
  'Page ${from + 1} moved to ${to + 1}',
  Directionality.of(context),
);
