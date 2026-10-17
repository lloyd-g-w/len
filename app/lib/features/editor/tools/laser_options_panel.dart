import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ink/tool_settings.dart';
import '../../../ui/adaptive_popover.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/color_picker/color_choices.dart';
import '../../../ui/group_header.dart';
import '../../../ui/roving_focus.dart';
import '../pen/option_controls.dart';
import '../pen/option_sections.dart';
import '../pen/pen_ends_options.dart';
import 'laser_preview.dart';
import 'laser_slots.dart';

/// The laser pointer's settings, laid out as the pen's: a title with Reset
/// (puts dot / trail, the trail's feel and the fading back to the defaults,
/// keeping the quick slots), a live preview, (in the phone sheet, which
/// covers the toolbar) the quick slots, then dot or trail, the colour and
/// size of the selected quick slots, the pen's feel for the trail
/// (pressure sensitivity, stabiliser, ends; greyed out for the dot), when
/// the trail fades (each stroke on its own, or all of it once the writing
/// stops) and how long it lasts, and, collapsed, how many quick colours and
/// sizes the toolbar shows. Edits apply live.
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
        final trail = laser.mode == LaserMode.trail;
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
            if (popoverIsSheet(context)) ...[
              const SizedBox(height: Gaps.sm),
              Row(
                children: [
                  LaserColorSlots(tools: tools, editable: false),
                  const Spacer(),
                  LaserSizeSlots(tools: tools, editable: false),
                ],
              ),
            ],
            const SizedBox(height: Gaps.sm),
            RovingSegments(
              SegmentedButton<LaserMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: LaserMode.dot,
                    icon: Icon(Symbols.circle_sharp, fill: 1, size: 12),
                    label: Text('Dot'),
                  ),
                  ButtonSegment(
                    value: LaserMode.trail,
                    icon: Icon(Symbols.gesture_sharp),
                    label: Text('Trail'),
                  ),
                ],
                selected: {laser.mode},
                onSelectionChanged: (s) => update(laser.copyWith(mode: s.single)),
              ),
            ),
            const SizedBox(height: Gaps.sm),
            ColorChoices(
              color: laser.color,
              palette: LaserConfig.presets,
              recent: tools.recentColors,
              onChanged: (c) => update(laser.withColor(laser.colorIndex, c)),
            ),
            const SizedBox(height: Gaps.sm),
            LaserSizeSlider(
              value: laser.size,
              onChanged: (v) => update(laser.withSize(laser.sizeIndex, v)),
            ),
            const OptionRule(),
            // The pen's feel, for the trail: greyed out for the dot, which
            // has no width to vary, no line to smooth and no ends.
            PressureSlider(
              value: laser.thinning,
              onChanged: trail ? (v) => update(tools.laser.copyWith(thinning: v)) : null,
            ),
            StabiliserSlider(
              value: laser.streamline,
              onChanged: trail ? (v) => update(tools.laser.copyWith(streamline: v)) : null,
            ),
            PenEndsOptions(
              ends: laser.ends,
              styles: LaserConfig.endStyles,
              onChanged: trail ? (ends) => update(tools.laser.copyWith(ends: ends)) : null,
            ),
            if (trail) ...[
              const OptionRule(),
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
            const SizedBox(height: Gaps.sm),
            QuickSlotCounts(
              colors: laser.colors.length,
              sizes: laser.sizes.length,
              min: LaserConfig.minSlots,
              max: LaserConfig.maxSlots,
              onAddColor: () => update(laser.addColor(_unusedColor(laser.colors))),
              onRemoveColor: () => update(laser.removeColor(laser.colors.length - 1)),
              onAddSize: () => update(laser.addSize(_newSize(laser))),
              onRemoveSize: () => update(laser.removeSize(laser.sizes.length - 1)),
            ),
          ],
        );
      },
    );
  }

  /// A palette colour not in the row yet, to start a new slot with.
  static int _unusedColor(List<int> used) => LaserConfig.presets.firstWhere(
    (c) => !used.contains(c),
    orElse: () => LaserConfig.presets.first,
  );

  /// A size for a new slot: a step above the last one, or below the
  /// current one when that would exceed the range.
  static double _newSize(LaserConfig c) {
    final up = (c.sizes.last * 1.5).roundToDouble();
    return (up <= LaserConfig.maxSize ? up : (c.size / 1.5).roundToDouble()).clamp(
      LaserConfig.minSize,
      LaserConfig.maxSize,
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
