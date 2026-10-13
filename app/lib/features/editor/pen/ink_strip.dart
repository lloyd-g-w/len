import 'package:flutter/material.dart';

import '../../../domain/stroke.dart';
import '../../../ink/tool_settings.dart';
import '../toolbar/toolbar_metrics.dart';
import 'ink_slots.dart';

/// The pen's or highlighter's quick controls: its colour slots, then its
/// width slots, 12 apart. Independent, so one tap changes either; the
/// selected one tapped again edits that slot alone. Slot counts (1–5
/// each) are set in the tool's options.
class InkStrip extends StatelessWidget {
  const InkStrip({super.key, required this.tools, required this.ink});

  final ToolSettings tools;
  final InkTool ink;

  /// Width the strip needs for [config] with [slot] cells.
  static double widthFor(PenConfig config, double slot) =>
      (config.colors.length + config.widths.length) * slot + ToolbarMetrics.groupGap;

  @override
  Widget build(BuildContext context) {
    return Flex(
      direction: ToolbarAxis.of(context),
      mainAxisSize: MainAxisSize.min,
      children: [
        ColorSlots(tools: tools, ink: ink),
        ToolbarAxis.gap(context, ToolbarMetrics.groupGap),
        WidthSlots(tools: tools, ink: ink),
      ],
    );
  }
}
