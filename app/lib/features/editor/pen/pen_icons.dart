import 'package:flutter/material.dart';

import '../../../domain/stroke.dart';

/// Toolbar icon for each ink tool.
IconData penIcon(InkTool tool) => switch (tool) {
  InkTool.ballpoint || InkTool.pen => Icons.edit_rounded,
  InkTool.fountain => Icons.history_edu_rounded,
  InkTool.brush => Icons.brush_rounded,
  InkTool.pencil => Icons.draw_rounded,
  InkTool.marker => Icons.format_paint_rounded,
  InkTool.highlighter => Icons.border_color_rounded,
};
