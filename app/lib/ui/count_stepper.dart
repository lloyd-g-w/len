import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'app_theme.dart';

/// "− 3 +": a small count stepped by one between [min] and [max] (a star's
/// points, a tool's quick slots in Settings).
class CountStepper extends StatelessWidget {
  const CountStepper({
    super.key,
    required this.noun,
    required this.count,
    required this.min,
    required this.max,
    required this.onAdd,
    required this.onRemove,
    this.compact = true,
  });

  /// Compact buttons (inside a popover's row); false gives them a full
  /// row's hit area ([Targets.menuRowHeight]: 44, or 48 on touch), as in
  /// Settings.
  final bool compact;

  /// Plural, lower case, read with the count ("5 points") and in the
  /// buttons' tooltips ("More points").
  final String noun;
  final int count;
  final int min;
  final int max;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget step(IconData icon, String tooltip, VoidCallback? onPressed) => IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: Glyphs.menu,
      visualDensity: compact ? VisualDensity.compact : null,
      constraints: compact
          ? null
          : BoxConstraints.tight(Size.square(Targets.menuRowHeight(context))),
      icon: Icon(icon),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        step(Symbols.remove_sharp, 'Fewer $noun', count > min ? onRemove : null),
        SizedBox(
          width: Gaps.xl,
          child: Text(
            '$count',
            textAlign: TextAlign.center,
            semanticsLabel: '$count $noun',
            style: text.labelLarge?.copyWith(fontFeatures: AppTheme.tabularFigures),
          ),
        ),
        step(Symbols.add_sharp, 'More $noun', count < max ? onAdd : null),
      ],
    );
  }
}

/// "Label − 3 +": a [CountStepper] at the end of a labelled row.
class StepperRow extends StatelessWidget {
  const StepperRow({
    super.key,
    required this.label,
    required this.noun,
    required this.count,
    required this.min,
    required this.max,
    required this.onAdd,
    required this.onRemove,
  });

  final String label;

  /// As [CountStepper.noun].
  final String noun;
  final int count;
  final int min;
  final int max;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(label, style: Theme.of(context).textTheme.labelLarge)),
      CountStepper(noun: noun, count: count, min: min, max: max, onAdd: onAdd, onRemove: onRemove),
    ],
  );
}
