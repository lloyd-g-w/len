import 'package:flutter/material.dart';

import '../../../domain/stroke.dart';
import '../../../ink/tool_settings.dart';
import '../toolbar/tool_cluster.dart';
import '../toolbar/toolbar_metrics.dart';
import 'ink_slots.dart';

/// The pen's or highlighter's quick controls in its sub-bar: its width
/// slots, a hairline, then its colour slots (as Notewise orders them).
/// Independent, so one tap changes either; the selected one tapped again
/// edits that slot alone. Slot counts (1–5 each) are set in Settings →
/// Toolbar.
class InkStrip extends StatelessWidget {
  const InkStrip({super.key, required this.tools, required this.ink});

  final ToolSettings tools;
  final InkTool ink;

  @override
  Widget build(BuildContext context) {
    return Flex(
      direction: ToolbarAxis.of(context),
      mainAxisSize: MainAxisSize.min,
      children: [
        WidthSlots(tools: tools, ink: ink),
        const ToolbarDivider(),
        ColorSlots(tools: tools, ink: ink),
      ],
    );
  }
}
