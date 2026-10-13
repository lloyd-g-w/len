import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_theme.dart';

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
    final check = AnimatedContainer(
      duration: Motion.fast,
      width: compact ? 20 : 24,
      height: compact ? 20 : 24,
      // A checkbox (DESIGN §6: 2-dp corners, blue when on), flat on the
      // cover. The same in light and dark mode: covers don't follow the
      // theme. A dark edge on white shows on light and dark covers alike.
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.xs),
        color: selected ? scheme.primary : Colors.white.withValues(alpha: 0.92),
        border: Border.all(color: selected ? Colors.white : Colors.black54, width: 1.5),
      ),
      child: selected
          ? Icon(Symbols.check_sharp, size: compact ? 14 : 18, color: scheme.onPrimary)
          : null,
    );
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
