import 'package:flutter/material.dart';

import '../../../domain/stroke.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/color_picker/color_hex.dart';
import '../../../ui/color_picker/color_swatches.dart';
import 'slot_button.dart';
import 'slot_editors.dart';

/// The active ink's quick colours: tap to use one, tap the selected one
/// again (or long-press / right-click any) to change it, "+" to add one.
class ColorSlots extends StatelessWidget {
  const ColorSlots({super.key, required this.tools, required this.ink});

  final ToolSettings tools;
  final InkTool ink;

  @override
  Widget build(BuildContext context) {
    final config = tools.configOf(ink);
    final scheme = Theme.of(context).colorScheme;
    final active = tools.tool != EditorTool.eraser;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < config.colors.length; i++)
          SlotButton(
            key: ValueKey('color-$i'),
            selected: active && i == config.colorIndex,
            tooltip: i < 9 ? 'Colour ${i + 1} (${i + 1})' : 'Colour ${i + 1}',
            semanticLabel: 'Colour ${i + 1}, ${ColorHex.rgb(config.colors[i])}',
            onSelect: () => tools.selectColor(i),
            onEdit: (anchor) => openColorSlotEditor(anchor, tools, ink, i),
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: Color(config.colors[i]),
                shape: BoxShape.circle,
                // Keeps white swatches visible on light chrome, black on dark.
                border: Border.all(color: scheme.outline.withValues(alpha: 0.5)),
              ),
            ),
          ),
        if (config.colors.length < PenConfig.maxSlots)
          AddSlotButton(
            key: const ValueKey('add-color'),
            tooltip: 'Add colour',
            onAdd: (anchor) {
              tools.updateConfig(ink, (c) => c.addColor(_unusedColor(c.colors)));
              openColorSlotEditor(anchor, tools, ink, tools.configOf(ink).colorIndex);
            },
          ),
      ],
    );
  }

  /// A palette colour not in the row yet, to start a new slot with.
  static int _unusedColor(List<int> used) => ColorSwatches.palette.firstWhere(
    (c) => !used.contains(c) && c != 0xFFFFFFFF,
    orElse: () => ColorSwatches.palette.first,
  );
}

/// The active ink's quick widths, shown as dots at (scaled) real size.
class WidthSlots extends StatelessWidget {
  const WidthSlots({super.key, required this.tools, required this.ink});

  final ToolSettings tools;
  final InkTool ink;

  /// Dot diameter for [width] of [ink], in logical pixels.
  static double dotSize(InkTool ink, double width) =>
      (3 + width * PenDefaults.of(ink).dotScale).clamp(4.0, 26.0);

  @override
  Widget build(BuildContext context) {
    final config = tools.configOf(ink);
    final scheme = Theme.of(context).colorScheme;
    final active = tools.tool != EditorTool.eraser;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < config.widths.length; i++)
          SlotButton(
            key: ValueKey('width-$i'),
            selected: active && i == config.widthIndex,
            tooltip: 'Width ${_format(config.widths[i])}',
            semanticLabel: 'Width ${i + 1}, ${_format(config.widths[i])}',
            onSelect: () => tools.selectWidth(i),
            onEdit: (anchor) => openWidthSlotEditor(anchor, tools, ink, i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: dotSize(ink, config.widths[i]),
              height: dotSize(ink, config.widths[i]),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active && i == config.widthIndex
                    ? scheme.onSurface
                    : scheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ),
        if (config.widths.length < PenConfig.maxSlots)
          AddSlotButton(
            key: const ValueKey('add-width'),
            tooltip: 'Add width',
            onAdd: (anchor) {
              tools.updateConfig(ink, (c) => c.addWidth(_newWidth(ink, c)));
              openWidthSlotEditor(anchor, tools, ink, tools.configOf(ink).widthIndex);
            },
          ),
      ],
    );
  }

  /// A width for a new slot: a step above the current one, or below it
  /// when that would exceed the range.
  static double _newWidth(InkTool ink, PenConfig c) {
    final d = PenDefaults.of(ink);
    final up = c.width * 1.5;
    return d.clampWidth(up <= d.maxWidth ? up : c.width / 1.5);
  }
}

String _format(double w) => w.toStringAsFixed(w < 10 ? 1 : 0);
