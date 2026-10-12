import 'package:flutter/material.dart';

import '../../../domain/stroke.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/color_picker/color_hex.dart';
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < config.colors.length; i++)
          SlotButton(
            key: ValueKey('color-$i'),
            selected: active && i == config.colorIndex,
            tooltip: i < 9 ? 'Colour ${i + 1} (${i + 1})' : 'Colour ${i + 1}',
            semanticLabel: 'Colour ${i + 1}, ${ColorHex.rgb(config.colors[i])}',
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

/// An ink's quick widths, shown as neutral dots at (scaled) real size.
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < config.widths.length; i++)
          SlotButton(
            key: ValueKey('width-$i'),
            selected: active && i == config.widthIndex,
            tooltip: 'Width ${formatWidth(config.widths[i])}',
            semanticLabel: 'Width ${i + 1}, ${formatWidth(config.widths[i])}',
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

/// A width as shown to the user: one decimal below 10.
String formatWidth(double w) => w.toStringAsFixed(w < 10 ? 1 : 0);
