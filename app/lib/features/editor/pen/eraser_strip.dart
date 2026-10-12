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

  /// Width of the strip in logical pixels.
  static double get width => EraserConfig.quickSizes.length * ToolbarMetrics.slot;

  @override
  Widget build(BuildContext context) {
    final eraser = tools.eraser;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, size) in EraserConfig.quickSizes.indexed)
          SlotButton(
            key: ValueKey('eraser-size-$i'),
            selected: eraser.radius == size,
            tooltip: 'Eraser size ${(size * 2).round()} px',
            semanticLabel: 'Eraser size ${(size * 2).round()} pixels',
            onSelect: () => tools.eraser = eraser.copyWith(radius: size),
            onEdit: (anchor) {
              tools.eraser = tools.eraser.copyWith(radius: size);
              onEdit(anchor);
            },
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
