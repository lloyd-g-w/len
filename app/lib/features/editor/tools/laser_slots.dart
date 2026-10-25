import 'package:flutter/material.dart';

import '../../../ink/tool_settings.dart';
import '../../../ui/adaptive_popover.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/color_picker/color_choices.dart';
import '../pen/option_controls.dart';
import '../pen/quick_slots.dart';
import '../pen/slot_editors.dart';
import 'laser_preview.dart';

/// The laser's quick colours, edited as an ink's: tap to use one; tap the
/// selected one again (or long-press / right-click any) to change it
/// ([LaserColorSlotEditor]).
class LaserColorSlots extends StatelessWidget {
  const LaserColorSlots({super.key, required this.tools});

  final ToolSettings tools;

  @override
  Widget build(BuildContext context) {
    final laser = tools.laser;
    return ColorSlotRow(
      colors: laser.colors,
      selected: tools.reading ? null : laser.colorIndex,
      onSelect: (i) => tools.laser = tools.laser.copyWith(colorIndex: i),
      onEdit: (anchor, i) => showColorSlotEditor(
        anchor,
        tools: tools,
        colorOf: () => tools.laser.colors.elementAtOrNull(i),
        builder: (_) => LaserColorSlotEditor(tools: tools, index: i),
      ),
    );
  }
}

/// The laser's quick sizes, as dots; edited as an ink's
/// ([LaserSizeSlotEditor]).
class LaserSizeSlots extends StatelessWidget {
  const LaserSizeSlots({super.key, required this.tools});

  final ToolSettings tools;

  /// Dot diameter for a laser [size], in logical pixels (as an ink's: 4–20).
  static double dotSize(double size) => (4 + size).clamp(4.0, 20.0);

  @override
  Widget build(BuildContext context) {
    final laser = tools.laser;
    return SizeSlotRow(
      diameters: [for (final s in laser.sizes) dotSize(s)],
      selected: tools.reading ? null : laser.sizeIndex,
      // Said as the size slider says it.
      describe: (i) => percent(
        (laser.sizes[i] - LaserConfig.minSize) / (LaserConfig.maxSize - LaserConfig.minSize),
      ),
      onSelect: (i) => tools.laser = tools.laser.copyWith(sizeIndex: i),
      onEdit: (anchor, i) => showAdaptivePopover<void>(
        context: anchor,
        width: WidthSlotEditor.width,
        builder: (_) => LaserSizeSlotEditor(tools: tools, index: i),
      ),
    );
  }
}

/// The colour of one of the laser's quick slots: palette, recent colours
/// and Custom.
class LaserColorSlotEditor extends StatelessWidget {
  const LaserColorSlotEditor({super.key, required this.tools, required this.index});

  final ToolSettings tools;
  final int index;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: tools,
    builder: (context, _) {
      final colors = tools.laser.colors;
      if (index >= colors.length) return const SizedBox.shrink();
      return KeyedSubtree(
        key: const ValueKey('color-slot-editor'),
        child: ColorChoices(
          color: colors[index],
          palette: LaserConfig.presets,
          recent: tools.recentColors,
          onChanged: (argb) => tools.laser = tools.laser.withColor(index, argb),
        ),
      );
    },
  );
}

/// The size of one of the laser's quick slots: a live preview, then the
/// slider.
class LaserSizeSlotEditor extends StatelessWidget {
  const LaserSizeSlotEditor({super.key, required this.tools, required this.index});

  final ToolSettings tools;
  final int index;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: tools,
    builder: (context, _) {
      final laser = tools.laser;
      if (index >= laser.sizes.length) return const SizedBox.shrink();
      return Column(
        key: const ValueKey('width-slot-editor'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LaserPreview(config: laser.copyWith(sizeIndex: index), height: 48),
          const SizedBox(height: Gaps.xs),
          LaserSizeSlider(
            value: laser.sizes[index],
            onChanged: (v) => tools.laser = tools.laser.withSize(index, v),
          ),
        ],
      );
    },
  );
}

/// The laser's size slider (whole pixels; no value shown: the size is on
/// screen, whatever the zoom, so there is no unit to read).
class LaserSizeSlider extends StatelessWidget {
  const LaserSizeSlider({super.key, required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => OptionSlider(
    label: 'Size',
    value: value,
    min: LaserConfig.minSize,
    max: LaserConfig.maxSize,
    showValue: false,
    display: (v) =>
        percent((v - LaserConfig.minSize) / (LaserConfig.maxSize - LaserConfig.minSize)),
    onChanged: (v) => onChanged(v.roundToDouble()),
  );
}
