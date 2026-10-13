import 'package:flutter/material.dart';

import '../../../ink/tool_settings.dart';
import '../toolbar/toolbar_metrics.dart';
import 'ink_slots.dart';
import 'slot_button.dart';

/// The eraser's quick controls: three size slots (· • ●), drawn as rings.
/// Whole stroke / partial lives in the eraser's options.
class EraserStrip extends StatelessWidget {
  const EraserStrip({super.key, required this.tools, required this.onEdit});

  final ToolSettings tools;

  /// Opens the eraser's options anchored to a slot.
  final SlotEdit onEdit;

  /// Width of the strip for a [slot] cell.
  static double widthFor(double slot) => EraserConfig.quickSizes.length * slot;

  @override
  Widget build(BuildContext context) {
    final eraser = tools.eraser;
    return Flex(
      direction: ToolbarAxis.of(context),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, size) in EraserConfig.quickSizes.indexed)
          SlotButton(
            key: ValueKey('eraser-size-$i'),
            selected: eraser.radius == size,
            tooltip: 'Eraser size ${i + 1}',
            semanticLabel: 'Eraser size ${i + 1}',
            onSelect: () => tools.eraser = eraser.copyWith(radius: size),
            onEdit: (anchor) {
              tools.eraser = tools.eraser.copyWith(radius: size);
              onEdit(anchor);
            },
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
