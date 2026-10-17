import 'package:flutter/material.dart';

import '../../../ink/tool_settings.dart';
import '../toolbar/toolbar_metrics.dart';
import 'laser_slots.dart';

/// The laser pointer's quick controls, as an ink's: its colour slots, then
/// its size slots, 12 apart; the selected one tapped again edits that slot.
/// Slot counts (1–5 each), Dot / Trail and the fading are in its options.
class LaserStrip extends StatelessWidget {
  const LaserStrip({super.key, required this.tools});

  final ToolSettings tools;

  /// Width the strip needs for [config] with [slot] cells.
  static double widthFor(LaserConfig config, double slot) =>
      (config.colors.length + config.sizes.length) * slot + ToolbarMetrics.groupGap;

  @override
  Widget build(BuildContext context) {
    return Flex(
      direction: ToolbarAxis.of(context),
      mainAxisSize: MainAxisSize.min,
      children: [
        LaserColorSlots(tools: tools),
        ToolbarAxis.gap(context, ToolbarMetrics.groupGap),
        LaserSizeSlots(tools: tools),
      ],
    );
  }
}
