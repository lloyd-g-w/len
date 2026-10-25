import 'package:flutter/material.dart';

import '../../../domain/stroke.dart';
import '../../../ink/pen/pen_config.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/group_header.dart';
import '../../../ui/roving_focus.dart';

/// Per-ink cap shape, one segmented control among [styles]
/// (`PenDefaults.endStyles`). The preview above it renders the selected
/// style with the same outline engine as saved strokes. Where a taper
/// starts and how long it is are not offered: their stored values (by
/// default both ends, four widths long) keep working.
class PenEndsOptions extends StatelessWidget {
  const PenEndsOptions({
    super.key,
    required this.ends,
    required this.styles,
    required this.onChanged,
  });

  final PenEnds ends;
  final List<StrokeEnds> styles;
  final ValueChanged<PenEnds> onChanged;

  static String _label(StrokeEnds style) => switch (style) {
    StrokeEnds.round => 'Round',
    StrokeEnds.tapered => 'Tapered',
    StrokeEnds.flat => 'Flat',
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Gaps.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const GroupHeader('Ends'),
          const SizedBox(height: Gaps.xs),
          RovingSegments(
            SegmentedButton<StrokeEnds>(
              showSelectedIcon: false,
              segments: [
                for (final style in styles) ButtonSegment(value: style, label: Text(_label(style))),
              ],
              selected: {ends.style},
              onSelectionChanged: (selected) => onChanged(ends.copyWith(style: selected.single)),
            ),
          ),
        ],
      ),
    );
  }
}
