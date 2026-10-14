import 'package:flutter/material.dart';

import '../../../domain/stroke.dart';
import '../../../domain/templates/paper_look.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/color_picker/color_names.dart';
import '../toolbar/toolbar_metrics.dart';
import 'slot_button.dart';
import 'slot_editors.dart';

/// Opens something anchored to a slot (see [SlotButton.onEdit]).
typedef SlotEdit = void Function(BuildContext anchor);

/// An ink's quick colours: tap to use one; tap the selected one again (or
/// long-press / right-click any) to change that slot's colour
/// ([editColorSlot]). The ink's other options open from its tool button.
class ColorSlots extends StatelessWidget {
  const ColorSlots({super.key, required this.tools, required this.ink, this.editable = true});

  final ToolSettings tools;
  final InkTool ink;

  /// Whether a slot opens its editor; false for the copy inside the tool
  /// options sheet, whose colour block edits the selected slot already.
  final bool editable;

  @override
  Widget build(BuildContext context) {
    final config = tools.configOf(ink);
    final active = !editable || tools.tool.usesInk;
    return Flex(
      direction: ToolbarAxis.of(context),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < config.colors.length; i++)
          SlotButton(
            key: ValueKey('color-$i'),
            selected: active && i == config.colorIndex,
            tabStop: i == (active ? config.colorIndex : 0),
            tooltip: i < 9 ? 'Colour ${i + 1} (${i + 1})' : 'Colour ${i + 1}',
            semanticLabel: 'Colour ${i + 1}, ${colorName(config.colors[i])}',
            editHint: 'Double tap to change this colour',
            onSelect: () => _select(i),
            onEdit: editable
                ? (anchor) {
                    _select(i);
                    editColorSlot(anchor, tools: tools, ink: ink, index: i);
                  }
                : null,
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
/// real size on a plate when selected. Tap the selected one again (or
/// long-press / right-click any) to change that size ([editWidthSlot]).
class WidthSlots extends StatelessWidget {
  const WidthSlots({super.key, required this.tools, required this.ink, this.editable = true});

  final ToolSettings tools;
  final InkTool ink;

  /// As [ColorSlots.editable].
  final bool editable;

  /// Dot diameter for [width] of [ink], in logical pixels (4–20).
  static double dotSize(InkTool ink, double width) =>
      (3 + width * PenDefaults.of(ink).dotScale).clamp(4.0, 20.0);

  @override
  Widget build(BuildContext context) {
    final config = tools.configOf(ink);
    final active = !editable || tools.tool.usesInk;
    return Flex(
      direction: ToolbarAxis.of(context),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < config.widths.length; i++)
          SlotButton(
            key: ValueKey('width-$i'),
            selected: active && i == config.widthIndex,
            tabStop: i == (active ? config.widthIndex : 0),
            tooltip: 'Size ${formatWidth(config.widths[i])}',
            semanticLabel: 'Size ${i + 1}, ${formatWidth(config.widths[i])}',
            editHint: 'Double tap to change this size',
            plate: true,
            onSelect: () => _select(i),
            onEdit: editable
                ? (anchor) {
                    _select(i);
                    editWidthSlot(anchor, tools: tools, ink: ink, index: i);
                  }
                : null,
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
/// page (as printed, and on screen at 100 %), to 0.05 mm below 1 mm:
/// "0.65 mm", "1.1 mm", "13 mm".
String formatWidth(double w) {
  final mm = w / PaperLook.unitsPerMm;
  final fine = (mm * 20).round() / 20;
  if (fine < 1) {
    final s = fine.toStringAsFixed(2);
    return '${s.endsWith('0') ? s.substring(0, s.length - 1) : s} mm';
  }
  return '${mm.toStringAsFixed(mm < 10 ? 1 : 0)} mm';
}
