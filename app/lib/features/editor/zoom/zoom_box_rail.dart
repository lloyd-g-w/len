import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_theme.dart';
import '../chrome/bar_button.dart';

/// The zoom window's rail at the box's right: ✕ (close) at the top, ↵
/// (next line) at the bottom, under the writing hand's reach. A box too
/// short for both keeps ✕ alone (↵ also comes by writing on).
class ZoomBoxRail extends StatelessWidget {
  const ZoomBoxRail({super.key, required this.onClose, required this.onNewLine});

  final VoidCallback onClose, onNewLine;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final close = BarButton(
      icon: Symbols.close_sharp,
      tooltip: 'Close zoom window',
      onPressed: onClose,
    );
    return DecoratedBox(
      decoration: BoxDecoration(border: Border(left: Surfaces.chromeEdge(scheme))),
      child: Padding(
        padding: const EdgeInsets.all(Gaps.xs),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final both = constraints.maxHeight >= 2 * Targets.barHit(context);
            if (!both) return Align(alignment: Alignment.topCenter, child: close);
            return Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                close,
                BarButton(
                  icon: Symbols.keyboard_return_sharp,
                  tooltip: 'Next line',
                  onPressed: onNewLine,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
