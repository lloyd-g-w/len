import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ink/tool_settings.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/roving_focus.dart';
import 'option_controls.dart';

/// The eraser's options (tap the selected eraser), one flat panel: a
/// title with Reset, whole stroke or partial, and "highlighter only"; with
/// scribble to erase on, a caption mentions it. Its size is the toolbar's
/// three size slots (a size set before keeps working until one is picked).
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
            RovingSegments(
              SegmentedButton<EraserMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: EraserMode.stroke,
                    icon: Icon(Symbols.gesture_sharp),
                    label: Text('Whole stroke'),
                  ),
                  ButtonSegment(
                    value: EraserMode.pixel,
                    icon: Icon(Symbols.blur_on_sharp),
                    label: Text('Partial'),
                  ),
                ],
                selected: {eraser.mode},
                onSelectionChanged: (s) => update(eraser.copyWith(mode: s.single)),
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
