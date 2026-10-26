import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'app_theme.dart';

/// The checkbox on a cover or a page thumbnail in selection mode (DESIGN
/// §6: 2-dp corners, blue when on), flat on the cover or paper. The same in
/// light and dark mode: covers and paper don't follow the theme, and a dark
/// edge on white shows on light and dark covers alike. It takes no taps:
/// the whole cover, row or tile toggles the selection.
class SelectCheck extends StatelessWidget {
  const SelectCheck({super.key, required this.selected, this.small = false});

  final bool selected;

  /// Small covers (the library's list rows): 20 dp instead of 24.
  final bool small;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final paper = Tones.light;
    final size = small ? 20.0 : 24.0;
    return AnimatedContainer(
      duration: Motion.fast,
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.xs),
        color: selected ? scheme.primary : paper.sheet.withValues(alpha: 0.92),
        border: Border.all(
          color: selected ? paper.sheet : paper.ink.withValues(alpha: 0.54),
          width: 1.5,
        ),
      ),
      child: selected ? Icon(Symbols.check_rounded, size: size - 6, color: scheme.onPrimary) : null,
    );
  }
}
