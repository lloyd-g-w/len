import 'package:flutter/material.dart';

import '../../../domain/stroke.dart';
import '../../../ink/tool_settings.dart';
import '../pen/ink_strip.dart';

/// The Shapes tool's quick controls: the pen's slots, since shapes are
/// drawn with the pen's colour and width. The kind is picked in the tool's
/// options (tap the Shapes button, which shows the current kind, or the
/// sub-bar's options button).
class ShapeStrip extends StatelessWidget {
  const ShapeStrip({super.key, required this.tools});

  final ToolSettings tools;

  @override
  Widget build(BuildContext context) => InkStrip(tools: tools, ink: InkTool.ballpoint);
}
