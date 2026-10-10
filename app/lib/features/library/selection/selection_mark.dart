import 'package:flutter/material.dart';

import '../../../ui/app_theme.dart';

/// Overlay on a cover in selection mode: a check circle, and a tinted
/// ring when selected.
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
        border: Border.all(color: selected ? Colors.white : scheme.outline, width: 2),
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 4)],
      ),
      child: selected
          ? Icon(Icons.check_rounded, size: compact ? 14 : 18, color: scheme.onPrimary)
          : null,
    );
    return IgnorePointer(
      child: AnimatedContainer(
        duration: Motion.fast,
        decoration: BoxDecoration(
          color: selected ? scheme.primary.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(compact ? Radii.xs : Radii.cover),
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
