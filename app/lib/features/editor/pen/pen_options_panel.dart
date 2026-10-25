import 'package:flutter/material.dart';

import '../../../domain/stroke.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/app_theme.dart';
import 'option_controls.dart';
import 'pen_ends_options.dart';
import 'stroke_preview.dart';

/// The pen's options (tap the selected pen): one flat panel with a title
/// and Reset (the feel back to its defaults), a live preview, pressure
/// sensitivity, stabiliser and the ends. Edits apply live. Colours and
/// widths are the toolbar's quick slots (their counts in Settings →
/// Toolbar), not options.
class PenOptionsPanel extends StatelessWidget {
  const PenOptionsPanel({super.key, required this.tools});

  final ToolSettings tools;

  static const InkTool ink = InkTool.ballpoint;

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
            InkOptionsHeader('Pen', tools: tools, ink: ink),
            const SizedBox(height: Gaps.sm),
            PreviewCard(tool: ink, config: config),
            PressureSlider(
              value: config.thinning,
              onChanged: (v) => update((c) => c.copyWith(thinning: v)),
            ),
            StabiliserSlider(
              value: config.streamline,
              onChanged: (v) => update((c) => c.copyWith(streamline: v)),
            ),
            PenEndsOptions(
              ends: config.ends,
              styles: PenDefaults.pen.endStyles,
              onChanged: (ends) => update((c) => c.copyWith(ends: ends)),
            ),
          ],
        );
      },
    );
  }
}
