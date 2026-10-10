import 'package:flutter/material.dart';

import '../../../domain/stroke.dart';
import '../../../ink/pen/pen_profile.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/adaptive_popover.dart';
import 'preset_editor.dart';

/// The three quick presets of the active pen (GoodNotes style). Tap to use
/// one; tap the selected one again, long-press or right-click to edit it.
class PresetStrip extends StatelessWidget {
  const PresetStrip({super.key, required this.tools});

  final ToolSettings tools;

  @override
  Widget build(BuildContext context) {
    final ink = tools.activeInk;
    final config = tools.configOf(ink);
    final profile = PenProfile.of(ink);
    final active = tools.tool.usesPresets;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < config.presets.length; i++)
          PresetDot(
            key: ValueKey('preset-$i'),
            preset: config.presets[i],
            opacity: config.opacity,
            sizeT:
                (config.presets[i].width - profile.minWidth) /
                (profile.maxWidth - profile.minWidth),
            selected: active && config.selected == i,
            onSelect: () => tools.selectPreset(i),
            onEdit: (context) => openPresetEditor(context, tools, ink, i),
          ),
      ],
    );
  }
}

/// Opens the editor for preset [index] of [ink], anchored to [context].
Future<void> openPresetEditor(BuildContext context, ToolSettings tools, InkTool ink, int index) {
  tools.selectPreset(index);
  return showAdaptivePopover<void>(
    context: context,
    builder: (_) => PresetEditor(tools: tools, ink: ink, index: index),
  );
}

/// One preset: a colour disc whose size hints at the width.
class PresetDot extends StatelessWidget {
  const PresetDot({
    super.key,
    required this.preset,
    required this.opacity,
    required this.sizeT,
    required this.selected,
    required this.onSelect,
    required this.onEdit,
  });

  final PenPreset preset;
  final double opacity;

  /// Width within the pen's range, 0..1.
  final double sizeT;
  final bool selected;
  final VoidCallback onSelect;
  final void Function(BuildContext anchor) onEdit;

  static const double _box = 36;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final disc = 12 + 14 * sizeT.clamp(0.0, 1.0);
    final color = Color(preset.color).withValues(alpha: opacity.clamp(0.25, 1.0));
    return Tooltip(
      message: selected ? 'Tap to edit' : 'Width ${preset.width.toStringAsFixed(1)}',
      child: Semantics(
        button: true,
        selected: selected,
        label: 'Preset',
        child: GestureDetector(
          onTap: () => selected ? onEdit(context) : onSelect(),
          onLongPress: () => onEdit(context),
          onSecondaryTap: () => onEdit(context),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: _box,
              height: _box,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? scheme.secondaryContainer : Colors.transparent,
                border: Border.all(color: selected ? scheme.primary : Colors.transparent, width: 2),
              ),
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: disc,
                  height: disc,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.outline.withValues(alpha: 0.35)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
