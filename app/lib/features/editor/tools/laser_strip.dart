import 'package:flutter/material.dart';

import '../../../ink/tool_settings.dart';
import '../../../ui/color_picker/color_hex.dart';
import '../pen/ink_slots.dart';
import '../pen/slot_button.dart';

/// The laser pointer's quick controls: three colour slots (red, green,
/// blue). More colours, Dot / Trail and the trail's length are in its
/// options.
class LaserStrip extends StatelessWidget {
  const LaserStrip({super.key, required this.tools, required this.onEdit});

  final ToolSettings tools;

  /// Opens the laser's options anchored to a slot.
  final SlotEdit onEdit;

  /// The quick colours: red, green and blue presets.
  static const List<int> colors = [0xFFFF2D2D, 0xFF2BD957, 0xFF2F8BFF];

  /// Width of the strip for a [slot] cell.
  static double widthFor(double slot) => colors.length * slot;

  @override
  Widget build(BuildContext context) {
    final laser = tools.laser;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, c) in colors.indexed)
          SlotButton(
            key: ValueKey('laser-slot-$i'),
            selected: laser.color == c,
            tooltip: 'Laser colour ${i + 1}',
            semanticLabel: 'Laser colour ${i + 1}, ${ColorHex.rgb(c)}',
            onSelect: () => tools.laser = laser.copyWith(color: c),
            onEdit: (anchor) {
              tools.laser = tools.laser.copyWith(color: c);
              onEdit(anchor);
            },
            child: SlotSwatch(color: c),
          ),
      ],
    );
  }
}
