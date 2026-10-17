import 'package:flutter/material.dart';

import '../../../domain/stroke.dart';
import '../../../ink/pen/pen_config.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/group_header.dart';
import '../../../ui/roving_focus.dart';
import 'option_controls.dart';

/// Per-ink cap shape, among [styles] (`PenDefaults.endStyles`; the laser's
/// trail offers the pen's). The preview above this control renders the
/// selected style using the same outline engine as saved strokes.
class PenEndsOptions extends StatelessWidget {
  const PenEndsOptions({
    super.key,
    required this.ends,
    required this.styles,
    required this.onChanged,
  });

  final PenEnds ends;
  final List<StrokeEnds> styles;

  /// Null greys the control out (ends that don't apply, as the laser's dot).
  final ValueChanged<PenEnds>? onChanged;

  static String _label(StrokeEnds style) => switch (style) {
    StrokeEnds.round => 'Round',
    StrokeEnds.tapered => 'Tapered',
    StrokeEnds.flat => 'Flat',
  };

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    final enabled = onChanged != null;
    return Padding(
      padding: const EdgeInsets.only(top: Gaps.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GroupHeader('Ends', enabled: enabled),
          const SizedBox(height: Gaps.xs),
          RovingSegments(
            SegmentedButton<StrokeEnds>(
              showSelectedIcon: false,
              segments: [
                for (final style in styles) ButtonSegment(value: style, label: Text(_label(style))),
              ],
              selected: {ends.style},
              onSelectionChanged: enabled
                  ? (selected) => onChanged(ends.copyWith(style: selected.single))
                  : null,
            ),
          ),
          if (ends.style == StrokeEnds.tapered) ...[
            const SizedBox(height: Gaps.sm),
            RovingSegments(
              SegmentedButton<TaperAt>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: TaperAt.start, label: Text('Start')),
                  ButtonSegment(value: TaperAt.end, label: Text('End')),
                  ButtonSegment(value: TaperAt.both, label: Text('Both')),
                ],
                selected: {ends.taperAt},
                onSelectionChanged: enabled
                    ? (selected) => onChanged(ends.copyWith(taperAt: selected.single))
                    : null,
              ),
            ),
            OptionSlider(
              label: 'Taper length',
              value: ends.taperLength,
              min: PenEnds.minTaperLength,
              max: PenEnds.maxTaperLength,
              display: (value) => '${value.toStringAsFixed(1)}× width',
              onChanged: enabled ? (value) => onChanged(ends.copyWith(taperLength: value)) : null,
            ),
          ],
        ],
      ),
    );
  }
}
