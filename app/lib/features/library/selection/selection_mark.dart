import 'package:flutter/material.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/select_check.dart';

/// Overlay on a cover in selection mode: a checkbox, and an accent ring
/// when selected. It takes no taps: the whole cover (or list row)
/// toggles the selection, so the target is far larger than the mark.
class SelectionMark extends StatelessWidget {
  const SelectionMark({super.key, required this.selected, this.compact = false});

  final bool selected;

  /// Small covers (list view): just the tint and a centred check.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final check = SelectCheck(selected: selected, small: compact);
    return IgnorePointer(
      child: AnimatedContainer(
        duration: Motion.fast,
        // Ring and check only: covers keep their own colours (never themed).
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(compact ? Radii.xs : Radii.sm),
          border: Border.all(
            color: selected ? scheme.primary : Colors.transparent,
            width: Hairline.rule,
          ),
        ),
        child: compact
            ? Center(child: check)
            : Align(
                alignment: Alignment.topLeft,
                child: Padding(padding: const EdgeInsets.all(Gaps.sm), child: check),
              ),
      ),
    );
  }
}
