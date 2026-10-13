import 'package:flutter/material.dart';

import '../../../domain/stroke.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/app_theme.dart';
import 'option_controls.dart';
import 'pen_ends_options.dart';
import 'stroke_preview.dart';

/// The pen's settings popover: a live preview, pressure sensitivity,
/// stabiliser and hold to snap. Edits apply live; Reset restores the feel
/// defaults. Quick colours and widths live in the toolbar itself.
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
            FeelHeader('Pen settings', tools: tools, ink: ink),
            const SizedBox(height: Gaps.sm),
            PreviewCard(tool: ink, config: config),
            OptionSlider(
              label: 'Pressure sensitivity',
              value: config.thinning,
              min: 0,
              max: 1,
              display: (v) => v == 0 ? 'Off' : percent(v),
              onChanged: (v) => update((c) => c.copyWith(thinning: v)),
            ),
            StabiliserSlider(
              value: config.streamline,
              onChanged: (v) => update((c) => c.copyWith(streamline: v)),
            ),
            PenEndsOptions(
              config: config,
              onChanged: (ends) => update((c) => c.copyWith(ends: ends)),
            ),
            HoldToSnapSwitch(tools: tools),
          ],
        );
      },
    );
  }
}

/// "Hold to snap shapes" (one setting for both inks); [enabled] false
/// greys it out where it does not apply.
class HoldToSnapSwitch extends StatelessWidget {
  const HoldToSnapSwitch({super.key, required this.tools, this.enabled = true});

  final ToolSettings tools;
  final bool enabled;

  @override
  Widget build(BuildContext context) => OptionSwitch(
    label: 'Hold to snap shapes',
    subtitle: 'Hold still at the end of a stroke for a clean line or shape',
    value: tools.holdToStraighten,
    onChanged: enabled ? (v) => tools.holdToStraighten = v : null,
  );
}
