import 'package:flutter/material.dart';

import '../../../ink/tool_settings.dart';
import '../toolbar/tool_cluster.dart';
import '../toolbar/toolbar_metrics.dart';
import 'laser_slots.dart';

/// The laser pointer's quick controls, as an ink's: its size slots, a
/// hairline, then its colour slots; the selected one tapped again edits
/// that slot. Slot counts (1–5 each) are in Settings → Toolbar; Dot /
/// Trail and the fading in its options.
class LaserStrip extends StatelessWidget {
  const LaserStrip({super.key, required this.tools});

  final ToolSettings tools;

  @override
  Widget build(BuildContext context) {
    return Flex(
      direction: ToolbarAxis.of(context),
      mainAxisSize: MainAxisSize.min,
      children: [
        LaserSizeSlots(tools: tools),
        const ToolbarDivider(),
        LaserColorSlots(tools: tools),
      ],
    );
  }
}
