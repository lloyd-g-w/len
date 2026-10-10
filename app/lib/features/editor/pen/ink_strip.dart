import 'package:flutter/material.dart';

import '../../../domain/stroke.dart';
import '../../../ink/tool_settings.dart';
import 'ink_slots.dart';
import 'slot_button.dart';

/// The pen's or highlighter's quick controls: its colour row and, beside
/// it, its width row — independent, so one tap changes either.
class InkStrip extends StatelessWidget {
  const InkStrip({super.key, required this.tools, required this.ink});

  final ToolSettings tools;
  final InkTool ink;

  /// Width the strip needs for [config] (for choosing the toolbar layout).
  static double widthFor(PenConfig config) {
    int row(int n) => n < PenConfig.maxSlots ? n + 1 : n;
    return (row(config.colors.length) + row(config.widths.length)) * SlotButton.size + 13;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ColorSlots(tools: tools, ink: ink),
        Container(
          width: 1,
          height: 20,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        WidthSlots(tools: tools, ink: ink),
      ],
    );
  }
}
