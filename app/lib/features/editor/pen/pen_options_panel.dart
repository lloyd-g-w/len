import 'package:flutter/material.dart';

import '../../../domain/stroke.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/app_theme.dart';
import 'option_controls.dart';
import 'stroke_preview.dart';

/// The compact settings popover of the pen (pressure sensitivity,
/// stabiliser) or the highlighter (opacity), plus hold to straighten. Edits apply live; quick colours and widths live in the
/// toolbar itself.
class PenOptionsPanel extends StatelessWidget {
  const PenOptionsPanel({super.key, required this.tools, required this.ink});

  final ToolSettings tools;

  /// [InkTool.ballpoint] (the pen) or [InkTool.highlighter].
  final InkTool ink;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tools,
      builder: (context, _) {
        final config = tools.configOf(ink);
        final defaults = PenDefaults.of(ink);
        void update(PenConfig Function(PenConfig) f) => tools.updateConfig(ink, f);
        final isPen = !ink.isHighlighter;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OptionHeader(
              '${defaults.label} settings',
              trailing: TextButton(
                onPressed: () => update((c) {
                  final d = PenConfig.defaultsFor(ink);
                  return c.copyWith(
                    opacity: d.opacity,
                    thinning: d.thinning,
                    streamline: d.streamline,
                  );
                }),
                child: const Text('Reset'),
              ),
            ),
            const SizedBox(height: Gaps.sm),
            PreviewCard(tool: ink, config: config),
            if (isPen) ...[
              OptionSlider(
                label: 'Pressure sensitivity',
                value: config.thinning,
                min: 0,
                max: 1,
                display: percent,
                onChanged: (v) => update((c) => c.copyWith(thinning: v)),
              ),
              OptionSlider(
                label: 'Stabiliser',
                value: config.streamline,
                min: 0,
                max: 0.95,
                display: percent,
                onChanged: (v) => update((c) => c.copyWith(streamline: v)),
              ),
            ] else
              OptionSlider(
                label: 'Opacity',
                value: config.opacity,
                min: PenConfig.minOpacity,
                max: 1,
                display: percent,
                onChanged: (v) => update((c) => c.copyWith(opacity: v)),
              ),
            OptionSwitch(
              label: 'Hold to snap shapes',
              subtitle: 'Pause at the end of a stroke to make it a straight line or a clean shape',
              value: tools.holdToStraighten,
              onChanged: (v) => tools.holdToStraighten = v,
            ),
          ],
        );
      },
    );
  }
}
