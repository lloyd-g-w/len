import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../ink/lab/input_recording.dart';
import '../../ui/menus.dart';

/// The Ink Lab's pen choices: stabiliser (streamline) and width.
class InkLabPenMenu extends StatelessWidget {
  const InkLabPenMenu({super.key, required this.pen, required this.onChanged});

  final PenSettings pen;
  final ValueChanged<PenSettings> onChanged;

  /// Stabiliser strengths offered (off, the default, strongest).
  static const List<double> streamlines = [0, 0.4, 1];

  /// Widths offered (world units).
  static const List<double> widths = [1.5, 2.5, 4];

  @override
  Widget build(BuildContext context) {
    return MenuIconButton<PenSettings>(
      tooltip: 'Pen',
      icon: const Icon(Symbols.edit_rounded),
      onSelected: onChanged,
      items: () => [
        MenuRow(value: pen, label: 'Stabiliser', enabled: false),
        for (final s in streamlines)
          MenuRow(
            value: pen.copyWith(streamline: s),
            label: s.toString(),
            checked: pen.streamline == s,
          ),
        const PopupMenuDivider(),
        MenuRow(value: pen, label: 'Width', enabled: false),
        for (final w in widths)
          MenuRow(
            value: pen.copyWith(width: w),
            label: w.toString(),
            checked: pen.width == w,
          ),
      ],
    );
  }
}
