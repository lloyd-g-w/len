import 'package:flutter/material.dart';

import '../../../ink/tool_settings.dart';
import '../../../ui/app_theme.dart';
import 'option_controls.dart';

/// The eraser's options (tap the selected eraser, or its sub-bar's options
/// button), one flat panel: a title with Reset and "highlighter only";
/// with scribble to erase on, a caption mentions it. Its size and whole
/// stroke or partial are in its sub-bar (a size set before keeps working
/// until one is picked).
class EraserOptionsPanel extends StatelessWidget {
  const EraserOptionsPanel({super.key, required this.tools});

  final ToolSettings tools;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tools,
      builder: (context, _) {
        final eraser = tools.eraser;
        void update(EraserConfig config) => tools.eraser = config;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OptionHeader(
              'Eraser',
              trailing: ResetButton<EraserConfig>(
                value: eraser,
                defaults: const EraserConfig(),
                onChanged: update,
              ),
            ),
            const SizedBox(height: Gaps.sm),
            OptionSwitch(
              label: 'Erase highlighter only',
              subtitle: 'Leaves pen ink untouched',
              value: eraser.highlighterOnly,
              onChanged: (v) => update(eraser.copyWith(highlighterOnly: v)),
            ),
            // The gesture that saves picking the eraser (Settings → Writing).
            if (tools.scribbleToErase) ...[
              const SizedBox(height: Gaps.sm),
              Text(
                'Or scribble over ink with the pen',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        );
      },
    );
  }
}
