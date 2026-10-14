import 'package:flutter/material.dart';

import '../../../domain/stroke.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/app_theme.dart';
import 'option_controls.dart';
import 'pen_ends_options.dart';
import 'stroke_preview.dart';

/// The highlighter's settings popover: a live preview, opacity, then the
/// pen's engine settings that make sense for a marker — pressure
/// sensitivity, stabiliser, ends (flat like a chisel tip, or round) — and
/// straight lines (the stabiliser greyed out while every stroke is
/// straight, as it does not apply). Edits apply live; Reset restores the
/// feel defaults.
class HighlighterOptionsPanel extends StatelessWidget {
  const HighlighterOptionsPanel({super.key, required this.tools});

  final ToolSettings tools;

  static const InkTool ink = InkTool.highlighter;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tools,
      builder: (context, _) {
        final config = tools.configOf(ink);
        void update(PenConfig Function(PenConfig) f) => tools.updateConfig(ink, f);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FeelHeader('Highlighter settings', tools: tools, ink: ink),
            const SizedBox(height: Gaps.sm),
            PreviewCard(tool: ink, config: config),
            OptionSlider(
              label: 'Opacity',
              value: config.opacity,
              min: PenConfig.minOpacity,
              max: 1,
              display: percent,
              onChanged: (v) => update((c) => c.copyWith(opacity: v)),
            ),
            PressureSlider(
              value: config.thinning,
              onChanged: (v) => update((c) => c.copyWith(thinning: v)),
            ),
            StabiliserSlider(
              value: config.streamline,
              onChanged: config.straight ? null : (v) => update((c) => c.copyWith(streamline: v)),
            ),
            PenEndsOptions(
              config: config,
              styles: PenDefaults.highlighter.endStyles,
              onChanged: (ends) => update((c) => c.copyWith(ends: ends)),
            ),
            OptionSwitch(
              label: 'Straight lines',
              subtitle: 'Every stroke is a straight line from where the pen went down',
              value: config.straight,
              onChanged: (v) => update((c) => c.copyWith(straight: v)),
            ),
          ],
        );
      },
    );
  }
}
