import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ink/tool_settings.dart';
import '../../../ui/app_theme.dart';
import 'option_controls.dart';

/// Eraser options: whole-stroke vs. partial erasing, size, "highlighter
/// only" and switching back to the previous tool after erasing.
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
            const SizedBox(height: Gaps.md),
            SegmentedButton<EraserMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: EraserMode.stroke,
                  icon: Icon(Symbols.gesture_rounded),
                  label: Text('Whole stroke'),
                ),
                ButtonSegment(
                  value: EraserMode.pixel,
                  icon: Icon(Symbols.blur_on_rounded),
                  label: Text('Partial'),
                ),
              ],
              selected: {eraser.mode},
              onSelectionChanged: (s) => update(eraser.copyWith(mode: s.single)),
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
            OptionSwitch(
              label: 'Erase highlighter only',
              subtitle: 'Leaves pen ink untouched',
              value: eraser.highlighterOnly,
              onChanged: (v) => update(eraser.copyWith(highlighterOnly: v)),
            ),
            OptionSwitch(
              label: 'Switch back after erasing',
              subtitle: 'Returns to your pen or highlighter',
              value: eraser.autoDeselect,
              onChanged: (v) => update(eraser.copyWith(autoDeselect: v)),
            ),
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
            color: scheme.onSurface.withValues(alpha: 0.08),
            border: Border.all(color: scheme.onSurface.withValues(alpha: 0.6)),
          ),
        ),
      ),
    );
  }
}
