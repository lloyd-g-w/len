import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_theme.dart';

/// Overlay on a cover in selection mode: a check circle, and a tinted
/// ring when selected. It takes no taps: the whole cover (or list row)
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
      width: compact ? 22 : 28,
      height: compact ? 22 : 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? scheme.primary : Colors.white.withValues(alpha: 0.92),
        // The same in light and dark mode: covers don't follow the theme. A
        // dark ring on white shows on light and dark covers alike.
        border: Border.all(color: selected ? Colors.white : Colors.black54, width: 2),
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 4)],
      ),
      child: selected
          ? Icon(Symbols.check_rounded, size: compact ? 14 : 18, color: scheme.onPrimary)
          : null,
    );
    return IgnorePointer(
      child: AnimatedContainer(
        duration: Motion.fast,
        decoration: BoxDecoration(
          color: selected ? scheme.primary.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(compact ? Radii.xs : Radii.sm),
          border: Border.all(
            color: selected ? scheme.primary : Colors.transparent,
            width: compact ? 2 : 3,
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
