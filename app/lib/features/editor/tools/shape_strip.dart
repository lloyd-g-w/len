import 'package:flutter/material.dart';

import '../../../domain/stroke.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/app_theme.dart';
import '../pen/ink_slots.dart';
import '../pen/ink_strip.dart';
import '../toolbar/toolbar_metrics.dart';
import 'tool_icons.dart';

/// The Shapes tool's quick controls: a button showing the current kind
/// (tap: the shape options, with every kind), then the pen's slots, since
/// shapes are drawn with the pen's colour and width.
class ShapeStrip extends StatelessWidget {
  const ShapeStrip({super.key, required this.tools, required this.onEdit, required this.onEditInk});

  final ToolSettings tools;

  /// Opens the shape options (the kinds).
  final SlotEdit onEdit;

  /// Opens the pen's options on one of its slots.
  final SlotEdit onEditInk;

  /// Width of the strip for the pen's current slots, with [slot] cells.
  static double widthFor(ToolSettings tools, double slot) =>
      slot + ToolbarMetrics.groupGap + InkStrip.widthFor(tools.configOf(InkTool.ballpoint), slot);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Builder(
          builder: (anchor) => IconButton(
            key: const ValueKey('shape-kind'),
            tooltip: '${tools.shape.label}: choose a shape',
            constraints: BoxConstraints.tight(Size.square(ToolbarMetrics.slotOf(context))),
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
              foregroundColor: scheme.onSurface,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.xs)),
            ),
            onPressed: () => onEdit(anchor),
            icon: ShapeGlyph(tools.shape, size: Glyphs.bar),
          ),
        ),
        const SizedBox(width: ToolbarMetrics.groupGap),
        InkStrip(tools: tools, ink: InkTool.ballpoint, onEdit: onEditInk),
      ],
    );
  }
}
