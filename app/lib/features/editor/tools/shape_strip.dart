import 'package:flutter/material.dart';

import '../../../domain/stroke.dart';
import '../../../ink/tool_settings.dart';
import '../pen/ink_slots.dart';
import '../pen/ink_strip.dart';

/// The Shapes tool's quick controls: the pen's slots, since shapes are
/// drawn with the pen's colour and size. The kind is picked in the tool's
/// options (tap the Shapes button, which shows the current kind).
class ShapeStrip extends StatelessWidget {
  const ShapeStrip({super.key, required this.tools, required this.onEditInk});

  final ToolSettings tools;

  /// Opens the pen's options on one of its slots.
  final SlotEdit onEditInk;

  /// Width of the strip for the pen's current slots, with [slot] cells.
  static double widthFor(ToolSettings tools, double slot) =>
      InkStrip.widthFor(tools.configOf(InkTool.ballpoint), slot);

  @override
  Widget build(BuildContext context) =>
      InkStrip(tools: tools, ink: InkTool.ballpoint, onEdit: onEditInk);
}
