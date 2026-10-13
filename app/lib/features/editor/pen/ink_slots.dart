import 'package:flutter/material.dart';

import '../../../domain/stroke.dart';
import '../../../domain/templates/paper_look.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/color_picker/color_names.dart';
import '../toolbar/toolbar_metrics.dart';
import 'slot_button.dart';

/// Opens the tool's options anchored to a slot (see [SlotButton.onEdit]).
typedef SlotEdit = void Function(BuildContext anchor);

/// An ink's quick colours: tap to use one; tap the selected one again
/// (or long-press / right-click any) for the options ([onEdit]).
class ColorSlots extends StatelessWidget {
  const ColorSlots({super.key, required this.tools, required this.ink, this.onEdit});

  final ToolSettings tools;
  final InkTool ink;

  /// Opens the options on a slot (it is selected first); null inside the
  /// options popover itself.
  final SlotEdit? onEdit;

  @override
  Widget build(BuildContext context) {
    final config = tools.configOf(ink);
    final active = onEdit == null || tools.tool.usesInk;
    final edit = onEdit;
    return Flex(
      direction: ToolbarAxis.of(context),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < config.colors.length; i++)
          SlotButton(
            key: ValueKey('color-$i'),
            selected: active && i == config.colorIndex,
            tooltip: i < 9 ? 'Colour ${i + 1} (${i + 1})' : 'Colour ${i + 1}',
            semanticLabel: 'Colour ${i + 1}, ${colorName(config.colors[i])}',
            onSelect: () => _select(i),
            onEdit: edit == null
                ? null
                : (anchor) {
                    _select(i);
                    edit(anchor);
                  },
            child: SlotSwatch(color: config.colors[i]),
          ),
      ],
    );
  }

  void _select(int i) {
    if (ink == InkTool.highlighter && tools.tool != EditorTool.highlighter) {
      tools.updateConfig(ink, (c) => c.copyWith(colorIndex: i));
    } else {
      tools.selectColor(i);
    }
  }
}

/// An ink's quick sizes (stroke widths), shown as neutral dots at (scaled)
/// real size on a plate when selected.
class WidthSlots extends StatelessWidget {
  const WidthSlots({super.key, required this.tools, required this.ink, this.onEdit});

  final ToolSettings tools;
  final InkTool ink;

  /// As [ColorSlots.onEdit].
  final SlotEdit? onEdit;

  /// Dot diameter for [width] of [ink], in logical pixels (4–20).
  static double dotSize(InkTool ink, double width) =>
      (3 + width * PenDefaults.of(ink).dotScale).clamp(4.0, 20.0);

  @override
  Widget build(BuildContext context) {
    final config = tools.configOf(ink);
    final active = onEdit == null || tools.tool.usesInk;
    final edit = onEdit;
    return Flex(
      direction: ToolbarAxis.of(context),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < config.widths.length; i++)
          SlotButton(
            key: ValueKey('width-$i'),
            selected: active && i == config.widthIndex,
            tooltip: 'Size ${formatWidth(config.widths[i])}',
            semanticLabel: 'Size ${i + 1}, ${formatWidth(config.widths[i])}',
            plate: true,
            onSelect: () => _select(i),
            onEdit: edit == null
                ? null
                : (anchor) {
                    _select(i);
                    edit(anchor);
                  },
            child: SlotDot(
              diameter: dotSize(ink, config.widths[i]),
              selected: active && i == config.widthIndex,
            ),
          ),
      ],
    );
  }

  void _select(int i) {
    if (ink == InkTool.highlighter && tools.tool != EditorTool.highlighter) {
      tools.updateConfig(ink, (c) => c.copyWith(widthIndex: i));
    } else {
      tools.selectWidth(i);
    }
  }
}

/// A stroke width (world units) as shown to the user: millimetres on the
/// page (as printed, and on screen at 100 %), "0.66 mm", "1.1 mm", "13 mm".
String formatWidth(double w) {
  final mm = w / PaperLook.unitsPerMm;
  return '${mm.toStringAsFixed(mm < 1 ? 2 : (mm < 10 ? 1 : 0))} mm';
}
