import 'package:flutter/material.dart';

import '../../../domain/stroke.dart';
import '../../../ink/pen/pen_profile.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/color_picker/color_picker.dart';
import 'option_controls.dart';
import 'stroke_preview.dart';

/// Edits one toolbar preset of [ink]: colour (full picker, with the pen's
/// opacity) and width. Changes apply live and select the preset.
class PresetEditor extends StatelessWidget {
  const PresetEditor({super.key, required this.tools, required this.ink, required this.index});

  final ToolSettings tools;
  final InkTool ink;
  final int index;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tools,
      builder: (context, _) {
        final config = tools.configOf(ink);
        final preset = config.presets[index];
        final profile = PenProfile.of(ink);
        final argb = (preset.color & 0xFFFFFF) | ((config.opacity * 255).round() << 24);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OptionHeader('${profile.label} · preset ${index + 1}'),
            const SizedBox(height: Gaps.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: Gaps.md, vertical: Gaps.xs),
              decoration: BoxDecoration(
                color: Palette.paper,
                borderRadius: BorderRadius.circular(Radii.control),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: StrokePreview(
                tool: ink,
                config: config.copyWith(selected: index),
                height: 48,
              ),
            ),
            OptionSlider(
              label: 'Width',
              value: preset.width,
              min: profile.minWidth,
              max: profile.maxWidth,
              display: (v) => v.toStringAsFixed(1),
              onChanged: (w) => _update(preset.copyWith(width: w)),
            ),
            const SizedBox(height: Gaps.sm),
            ColorPicker(
              color: argb,
              favorites: tools.favorites,
              onAddFavorite: tools.addFavorite,
              onRemoveFavorite: tools.removeFavorite,
              onChanged: (c) => _update(
                preset.copyWith(color: c | 0xFF000000),
                opacity: ((c >>> 24) & 0xFF) / 255,
              ),
            ),
          ],
        );
      },
    );
  }

  void _update(PenPreset preset, {double? opacity}) {
    tools.updateConfig(
      ink,
      (c) => c
          .withPreset(index, preset)
          .copyWith(selected: index, opacity: opacity?.clamp(PenConfig.minOpacity, 1.0)),
    );
  }
}
