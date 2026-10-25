import 'package:flutter/material.dart';

import '../../../ink/tool_settings.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/roving_focus.dart';
import '../tools/tool_icons.dart';
import 'option_controls.dart';
import 'slot_button.dart';

/// Eraser options: whole-stroke vs. partial erasing, size and "highlighter
/// only"; with scribble to erase on, a caption mentions it.
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
                    icon: ToolIcon(ToolIconKind.eraseStroke),
                    label: Text('Whole stroke'),
                  ),
                  ButtonSegment(
                    value: EraserMode.pixel,
                    icon: ToolIcon(ToolIconKind.erasePartial),
                    label: Text('Partial'),
                  ),
                ],
                selected: {eraser.mode},
                onSelectionChanged: (s) => update(eraser.copyWith(mode: s.single)),
              ),
            ),
            const SizedBox(height: Gaps.sm),
            Row(
              children: [
                Expanded(
                  child: OptionSlider(
                    label: 'Size',
                    value: eraser.radius,
                    min: EraserConfig.minRadius,
                    max: EraserConfig.maxRadius,
                    // On screen, whatever the zoom: the dot beside it shows it.
                    showValue: false,
                    display: (v) => percent(
                      (v - EraserConfig.minRadius) /
                          (EraserConfig.maxRadius - EraserConfig.minRadius),
                    ),
                    onChanged: (v) => update(eraser.copyWith(radius: v)),
                  ),
                ),
                const SizedBox(width: Gaps.sm),
                _SizePreview(radius: eraser.radius),
              ],
            ),
            const OptionRule(),
            OptionSwitch(
              label: 'Erase highlighter only',
              subtitle: 'Leaves pen ink untouched',
              value: eraser.highlighterOnly,
              onChanged: (v) => update(eraser.copyWith(highlighterOnly: v)),
            ),
            // The gesture that saves picking the eraser (Settings → Writing).
            if (tools.scribbleToErase) ...[
              const OptionRule(),
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

class _SizePreview extends StatelessWidget {
  const _SizePreview({required this.radius});

  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const box = EraserConfig.maxRadius;
    return SizedBox.square(
      dimension: box,
      child: Center(
        child: Container(
          width: (radius * 2).clamp(4, box),
          height: (radius * 2).clamp(4, box),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Surfaces.pressed(scheme),
            border: Border.all(color: scheme.onSurfaceVariant, width: SlotButton.ringWidth),
          ),
        ),
      ),
    );
  }
}
