import 'package:flutter/material.dart';

import '../../../ink/tool_settings.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/group_header.dart';
import '../../../ui/roving_focus.dart';
import '../pen/option_controls.dart';
import 'laser_preview.dart';
import 'tool_icons.dart';

/// The laser pointer's options (tap the selected laser), flat as the
/// pen's: a title with Reset (everything but the quick slots back to the
/// defaults), a live preview, dot or trail and, for the trail, when it
/// fades (each stroke on its own, or all of it once the writing stops) and
/// how long it lasts. Colours and sizes are the toolbar's quick slots. The
/// trail's pen feel (pressure, stabiliser, ends) is not offered: its stored
/// values keep working, and Reset puts them back. Edits apply live.
class LaserOptionsPanel extends StatelessWidget {
  const LaserOptionsPanel({super.key, required this.tools});

  final ToolSettings tools;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tools,
      builder: (context, _) {
        final laser = tools.laser;
        void update(LaserConfig config) => tools.laser = config;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OptionHeader(
              'Laser pointer',
              trailing: ResetButton<LaserConfig>(
                value: laser,
                defaults: laser.withFeelDefaults(),
                onChanged: update,
              ),
            ),
            const SizedBox(height: Gaps.sm),
            LaserPreview(config: laser),
            const SizedBox(height: Gaps.sm),
            RovingSegments(
              SegmentedButton<LaserMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: LaserMode.dot,
                    icon: ToolIcon(ToolIconKind.laserDot),
                    label: Text('Dot'),
                  ),
                  ButtonSegment(
                    value: LaserMode.trail,
                    icon: ToolIcon(ToolIconKind.laserTrail),
                    label: Text('Trail'),
                  ),
                ],
                selected: {laser.mode},
                onSelectionChanged: (s) => update(laser.copyWith(mode: s.single)),
              ),
            ),
            if (laser.mode == LaserMode.trail) ...[
              const SizedBox(height: Gaps.md),
              const GroupHeader('Fade'),
              const SizedBox(height: Gaps.xs),
              RovingSegments(
                SegmentedButton<LaserFade>(
                  showSelectedIcon: false,
                  segments: [
                    for (final fade in LaserFade.values)
                      ButtonSegment(value: fade, label: Text(fade.label)),
                  ],
                  selected: {laser.fade},
                  onSelectionChanged: (s) => update(tools.laser.copyWith(fade: s.single)),
                ),
              ),
              const SizedBox(height: Gaps.sm),
              if (laser.fade == LaserFade.stroke)
                _Seconds(
                  label: 'Trail lasts',
                  value: laser.duration,
                  min: LaserConfig.minDuration,
                  max: LaserConfig.maxDuration,
                  onChanged: (d) => update(tools.laser.copyWith(duration: d)),
                )
              else
                // "When I stop" says the rest: nothing fades while writing.
                _Seconds(
                  label: 'Fades after',
                  value: laser.hold,
                  min: LaserConfig.minHold,
                  max: LaserConfig.maxHold,
                  onChanged: (d) => update(tools.laser.copyWith(hold: d)),
                ),
            ],
          ],
        );
      },
    );
  }
}

/// A slider of seconds in tenths.
class _Seconds extends StatelessWidget {
  const _Seconds({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final Duration value, min, max;
  final ValueChanged<Duration> onChanged;

  @override
  Widget build(BuildContext context) => OptionSlider(
    label: label,
    value: value.inMilliseconds / 1000,
    min: min.inMilliseconds / 1000,
    max: max.inMilliseconds / 1000,
    display: (v) => '${v.toStringAsFixed(1)} s',
    onChanged: (v) => onChanged(Duration(milliseconds: (v * 10).round() * 100)),
  );
}
