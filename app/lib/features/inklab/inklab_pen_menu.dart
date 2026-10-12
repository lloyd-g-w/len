import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../ink/lab/input_recording.dart';

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
    return PopupMenuButton<PenSettings>(
      tooltip: 'Pen',
      icon: const Icon(Symbols.edit_rounded),
      onSelected: onChanged,
      itemBuilder: (context) => [
        const PopupMenuItem(enabled: false, height: 32, child: Text('Stabiliser')),
        for (final s in streamlines)
          CheckedPopupMenuItem(
            value: pen.copyWith(streamline: s),
            checked: pen.streamline == s,
            child: Text(s.toString()),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(enabled: false, height: 32, child: Text('Width')),
        for (final w in widths)
          CheckedPopupMenuItem(
            value: pen.copyWith(width: w),
            checked: pen.width == w,
            child: Text(w.toString()),
          ),
      ],
    );
  }
}
