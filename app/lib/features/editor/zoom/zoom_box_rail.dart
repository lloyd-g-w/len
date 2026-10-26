import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/menus.dart';
import '../chrome/bar_button.dart';

/// The zoom window's rail at the box's right: ✕ (close) and ⋯ (the box's
/// menu) at the top, ↵ (next line) at the bottom, under the writing
/// hand's reach. A box too short for all three keeps ✕ and ↵ (↵ also
/// comes by writing on), then ✕ alone. Right to left, ↵ points the way a
/// new line goes: back to the right.
class ZoomBoxRail<T> extends StatelessWidget {
  const ZoomBoxRail({
    super.key,
    required this.onClose,
    required this.onNewLine,
    required this.menu,
    required this.onMenu,
    this.rightToLeft = false,
  });

  final VoidCallback onClose, onNewLine;

  /// Whether lines run right to left (↵ is mirrored).
  final bool rightToLeft;

  /// The rows of the box's menu, and what to do with the one chosen.
  final List<PopupMenuEntry<T>> Function() menu;
  final ValueChanged<T> onMenu;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final close = BarButton(
      icon: Symbols.close_rounded,
      tooltip: 'Close zoom window',
      onPressed: onClose,
    );
    final more = Builder(
      builder: (anchor) => BarButton(
        icon: Symbols.more_horiz_rounded,
        tooltip: 'Zoom window options',
        onPressed: () => unawaited(_openMenu(anchor)),
      ),
    );
    final newLine = Transform.flip(
      flipX: rightToLeft,
      child: BarButton(
        icon: Symbols.keyboard_return_rounded,
        tooltip: 'Next line',
        onPressed: onNewLine,
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(border: Border(left: Surfaces.chromeEdge(scheme))),
      child: Padding(
        padding: const EdgeInsets.all(Gaps.xs),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final fits = (constraints.maxHeight / Targets.barHit(context)).floor();
            if (fits < 2) return Align(alignment: Alignment.topCenter, child: close);
            return Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(mainAxisSize: MainAxisSize.min, children: [close, if (fits >= 3) more]),
                newLine,
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _openMenu(BuildContext anchor) async {
    final choice = await showMenuBelow<T>(anchor, items: menu());
    if (choice != null) onMenu(choice);
  }
}
