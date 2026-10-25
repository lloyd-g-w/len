import 'package:flutter/material.dart';

import '../../../ui/color_picker/color_names.dart';
import '../toolbar/toolbar_metrics.dart';
import 'slot_button.dart';

/// Opens a slot's editor for slot `index`, anchored to the slot.
typedef SlotIndexEdit = void Function(BuildContext anchor, int index);

/// A row of quick colour slots (the pen's, the highlighter's, the
/// laser's): tap to use one; tap the selected one again (or long-press /
/// right-click any) to change it ([onEdit]). Laid out along the toolbar.
class ColorSlotRow extends StatelessWidget {
  const ColorSlotRow({
    super.key,
    required this.colors,
    required this.selected,
    required this.onSelect,
    this.onEdit,
  });

  /// Opaque ARGB.
  final List<int> colors;

  /// The selected slot; null shows none selected (another tool in hand).
  final int? selected;
  final ValueChanged<int> onSelect;

  /// Null: the slots open no editor (the copy inside the options sheet).
  final SlotIndexEdit? onEdit;

  @override
  Widget build(BuildContext context) {
    final edit = onEdit;
    return Flex(
      direction: ToolbarAxis.of(context),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < colors.length; i++)
          SlotButton(
            key: ValueKey('color-$i'),
            selected: i == selected,
            tabStop: i == (selected ?? 0),
            // 1–9 pick the quick colours of the tool in hand.
            tooltip: i < 9 ? 'Colour ${i + 1} (${i + 1})' : 'Colour ${i + 1}',
            semanticLabel: 'Colour ${i + 1}, ${colorName(colors[i])}',
            editHint: 'Double tap to change this colour',
            onSelect: () => onSelect(i),
            onEdit: edit == null
                ? null
                : (anchor) {
                    onSelect(i);
                    edit(anchor, i);
                  },
            child: SlotSwatch(color: colors[i]),
          ),
      ],
    );
  }
}

/// A row of quick size slots, shown as neutral dots ([diameters]) or, for
/// stroke widths, as [lines] of increasing thickness; the selected one has
/// the accent rule under it. Edited as [ColorSlotRow]'s colours.
class SizeSlotRow extends StatelessWidget {
  const SizeSlotRow({
    super.key,
    required this.diameters,
    required this.selected,
    required this.onSelect,
    this.describe,
    this.onEdit,
    this.lines = false,
  });

  /// Each slot's dot, in logical pixels.
  final List<double> diameters;

  /// Draws the sizes as lines ([SlotLine.thicknessFor] the dot) rather
  /// than dots: stroke widths.
  final bool lines;

  /// As [ColorSlotRow.selected].
  final int? selected;
  final ValueChanged<int> onSelect;

  /// Slot `i`'s size as read ("0.65 mm"); null: sizes go by number.
  final String Function(int i)? describe;

  /// As [ColorSlotRow.onEdit].
  final SlotIndexEdit? onEdit;

  @override
  Widget build(BuildContext context) {
    final edit = onEdit;
    final describe = this.describe;
    return Flex(
      direction: ToolbarAxis.of(context),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < diameters.length; i++)
          SlotButton(
            key: ValueKey('width-$i'),
            selected: i == selected,
            tabStop: i == (selected ?? 0),
            tooltip: describe == null ? 'Size ${i + 1}' : 'Size ${describe(i)}',
            semanticLabel: describe == null ? 'Size ${i + 1}' : 'Size ${i + 1}, ${describe(i)}',
            editHint: 'Double tap to change this size',
            rule: true,
            onSelect: () => onSelect(i),
            onEdit: edit == null
                ? null
                : (anchor) {
                    onSelect(i);
                    edit(anchor, i);
                  },
            child: lines
                ? SlotLine(thickness: SlotLine.thicknessFor(diameters[i]), selected: i == selected)
                : SlotDot(diameter: diameters[i], selected: i == selected),
          ),
      ],
    );
  }
}
