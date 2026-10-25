import 'package:flutter/material.dart';

import '../../../ink/tool_settings.dart';
import '../toolbar/toolbar_metrics.dart';
import 'slot_button.dart';

/// The eraser's quick controls: three size slots (· • ●), drawn as rings.
/// Whole stroke / partial lives in the eraser's options (tap the selected
/// eraser); a slot has nothing more to edit.
class EraserStrip extends StatelessWidget {
  const EraserStrip({super.key, required this.tools});

  final ToolSettings tools;

  /// Width of the strip for a [slot] cell.
  static double widthFor(double slot) => EraserConfig.quickSizes.length * slot;

  @override
  Widget build(BuildContext context) {
    final eraser = tools.eraser;
    final chosen = EraserConfig.quickSizes.indexOf(eraser.radius);
    return Flex(
      direction: ToolbarAxis.of(context),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, size) in EraserConfig.quickSizes.indexed)
          SlotButton(
            key: ValueKey('eraser-size-$i'),
            selected: eraser.radius == size,
            tabStop: i == (chosen < 0 ? 0 : chosen),
            tooltip: 'Eraser size ${i + 1}',
            semanticLabel: 'Eraser size ${i + 1}',
            onSelect: () => tools.eraser = eraser.copyWith(radius: size),
            plate: true,
            child: SlotDot(
              diameter: (4 + size * 0.5).clamp(6.0, 20.0),
              selected: eraser.radius == size,
              hollow: true,
            ),
          ),
      ],
    );
  }
}
