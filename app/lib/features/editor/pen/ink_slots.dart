import 'package:flutter/material.dart';

import '../../../domain/stroke.dart';
import '../../../domain/templates/paper_look.dart';
import '../../../ink/tool_settings.dart';
import 'quick_slots.dart';
import 'slot_editors.dart';

/// Opens something anchored to a slot (see [SlotButton.onEdit]).
typedef SlotEdit = void Function(BuildContext anchor);

/// An ink's quick colours ([ColorSlotRow]): tap to use one; tap the
/// selected one again (or long-press / right-click any) to change that
/// slot's colour ([editColorSlot]). The ink's other options open from its
/// tool button.
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
    final active = !editable || (tools.tool.usesInk && !tools.reading);
    return ColorSlotRow(
      colors: config.colors,
      selected: active ? config.colorIndex : null,
      onSelect: _select,
      onEdit: editable
          ? (anchor, i) => editColorSlot(anchor, tools: tools, ink: ink, index: i)
          : null,
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

/// An ink's quick sizes (stroke widths, [SizeSlotRow]), shown as neutral
/// dots at (scaled) real size. Tap the selected one again (or long-press /
/// right-click any) to change that size ([editWidthSlot]).
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
    final active = !editable || (tools.tool.usesInk && !tools.reading);
    return SizeSlotRow(
      diameters: [for (final w in config.widths) dotSize(ink, w)],
      selected: active ? config.widthIndex : null,
      describe: (i) => formatWidth(config.widths[i]),
      onSelect: _select,
      onEdit: editable
          ? (anchor, i) => editWidthSlot(anchor, tools: tools, ink: ink, index: i)
          : null,
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
