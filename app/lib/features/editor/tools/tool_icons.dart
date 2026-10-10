import 'package:flutter/material.dart';

import '../../../ink/tool_settings.dart';

/// Toolbar / picker icon for each shape.
IconData shapeIcon(ShapeKind kind) => switch (kind) {
  ShapeKind.line => Icons.horizontal_rule_rounded,
  ShapeKind.arrow => Icons.arrow_right_alt_rounded,
  ShapeKind.rectangle => Icons.crop_square_rounded,
  ShapeKind.ellipse => Icons.circle_outlined,
  ShapeKind.triangle => Icons.change_history_rounded,
  ShapeKind.diamond => Icons.diamond_outlined,
  ShapeKind.star => Icons.star_outline_rounded,
  ShapeKind.polygon => Icons.pentagon_outlined,
};

const IconData lassoIcon = Icons.highlight_alt_rounded;
const IconData textIcon = Icons.text_fields_rounded;
const IconData laserIcon = Icons.ads_click_rounded;
