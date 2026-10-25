import 'package:flutter/material.dart';

import '../../../domain/stroke.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/app_theme.dart';
import 'option_controls.dart';
import 'pen_ends_options.dart';
import 'stroke_preview.dart';

/// The highlighter's options (tap the selected highlighter), flat as the
/// pen's: a title with Reset, a live preview, opacity, stabiliser (greyed
/// out while every stroke is straight, as it does not apply), the ends
/// (flat like a chisel tip, or round), straight lines and snapping to PDF
/// text. Pressure sensitivity (off by default) is not offered: Reset puts
/// a stored one back to off. Edits apply live.
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
            InkOptionsHeader('Highlighter', tools: tools, ink: ink),
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
            StabiliserSlider(
              value: config.streamline,
              onChanged: config.straight ? null : (v) => update((c) => c.copyWith(streamline: v)),
            ),
            PenEndsOptions(
              ends: config.ends,
              styles: PenDefaults.highlighter.endStyles,
              onChanged: (ends) => update((c) => c.copyWith(ends: ends)),
            ),
            const SizedBox(height: Gaps.sm),
            OptionSwitch(
              label: 'Straight lines',
              value: config.straight,
              onChanged: (v) => update((c) => c.copyWith(straight: v)),
            ),
            OptionSwitch(
              label: 'Snap to text',
              subtitle: 'Highlights over PDF text cover whole words',
              value: config.snapToText,
              onChanged: (v) => update((c) => c.copyWith(snapToText: v)),
            ),
          ],
        );
      },
    );
  }
}
