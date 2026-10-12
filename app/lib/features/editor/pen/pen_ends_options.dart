import 'package:flutter/material.dart';

import '../../../domain/stroke.dart';
import '../../../ink/pen/pen_config.dart';
import '../../../ui/app_theme.dart';
import 'option_controls.dart';

/// Per-pen cap shape. The preview above this control renders the selected
/// style using the same outline builder as saved strokes.
class PenEndsOptions extends StatelessWidget {
  const PenEndsOptions({super.key, required this.config, required this.onChanged});

  final PenConfig config;
  final ValueChanged<PenEnds> onChanged;

  @override
  Widget build(BuildContext context) {
    final ends = config.ends;
    return Padding(
      padding: const EdgeInsets.only(top: Gaps.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const OptionHeader('Ends'),
          const SizedBox(height: Gaps.xs),
          SegmentedButton<StrokeEnds>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: StrokeEnds.round, label: Text('Round')),
              ButtonSegment(value: StrokeEnds.tapered, label: Text('Tapered')),
              ButtonSegment(value: StrokeEnds.flat, label: Text('Flat')),
            ],
            selected: {ends.style},
            onSelectionChanged: (selected) => onChanged(ends.copyWith(style: selected.single)),
          ),
          if (ends.style == StrokeEnds.tapered) ...[
            const SizedBox(height: Gaps.sm),
            SegmentedButton<TaperAt>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: TaperAt.start, label: Text('Start')),
                ButtonSegment(value: TaperAt.end, label: Text('End')),
                ButtonSegment(value: TaperAt.both, label: Text('Both')),
              ],
              selected: {ends.taperAt},
              onSelectionChanged: (selected) => onChanged(ends.copyWith(taperAt: selected.single)),
            ),
            OptionSlider(
              label: 'Taper length',
              value: ends.taperLength,
              min: PenEnds.minTaperLength,
              max: PenEnds.maxTaperLength,
              display: (value) => '${value.toStringAsFixed(1)}× width',
              onChanged: (value) => onChanged(ends.copyWith(taperLength: value)),
            ),
            if (ends.taperAt.atEnd)
              OptionSwitch(
                label: 'Follow pen speed',
                subtitle: 'Quick lifts make a longer tail; slow stops make a shorter one',
                value: ends.followSpeed,
                onChanged: (value) => onChanged(ends.copyWith(followSpeed: value)),
              ),
          ],
        ],
      ),
    );
  }
}
