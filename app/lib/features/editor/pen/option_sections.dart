import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_theme.dart';

/// "Quick colours − 3 +": how many quick slots of a kind the toolbar shows.
class SlotCountRow extends StatelessWidget {
  const SlotCountRow({
    super.key,
    required this.noun,
    required this.count,
    required this.min,
    required this.max,
    required this.onAdd,
    required this.onRemove,
  });

  /// Plural, lower case ("colours").
  final String noun;
  final int count;
  final int min;
  final int max;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => StepperRow(
    label: 'Quick $noun',
    noun: 'quick $noun',
    count: count,
    min: min,
    max: max,
    onAdd: onAdd,
    onRemove: onRemove,
  );
}

/// "Label − 3 +": a small count stepped by one ([SlotCountRow], a star's
/// points).
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

  /// Plural, lower case, read with the count ("5 points").
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
      visualDensity: VisualDensity.compact,
      icon: Icon(icon),
    );
    return Row(
      children: [
        Expanded(child: Text(label, style: text.labelLarge)),
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
