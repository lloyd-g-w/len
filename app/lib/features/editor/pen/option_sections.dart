import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/option_disclosure.dart';

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

/// "Quick colours and sizes" (summary "3 and 3"), collapsed: how many
/// quick colour and size slots ([min]..[max] each) a tool's strip shows —
/// the pen's, the highlighter's and the laser's. Open or not is
/// remembered while the app runs.
class QuickSlotCounts extends StatefulWidget {
  const QuickSlotCounts({
    super.key,
    required this.colors,
    required this.sizes,
    required this.min,
    required this.max,
    required this.onAddColor,
    required this.onRemoveColor,
    required this.onAddSize,
    required this.onRemoveSize,
  });

  /// How many colour and size slots there are.
  final int colors, sizes;
  final int min, max;
  final VoidCallback onAddColor, onRemoveColor, onAddSize, onRemoveSize;

  @override
  State<QuickSlotCounts> createState() => _QuickSlotCountsState();
}

class _QuickSlotCountsState extends State<QuickSlotCounts> {
  static bool _open = false;

  @override
  Widget build(BuildContext context) => OptionDisclosure(
    label: 'Quick colours and sizes',
    summary: '${widget.colors} and ${widget.sizes}',
    open: _open,
    onToggle: () => setState(() => _open = !_open),
    child: Column(
      children: [
        SlotCountRow(
          noun: 'colours',
          count: widget.colors,
          min: widget.min,
          max: widget.max,
          onAdd: widget.onAddColor,
          onRemove: widget.onRemoveColor,
        ),
        SlotCountRow(
          noun: 'sizes',
          count: widget.sizes,
          min: widget.min,
          max: widget.max,
          onAdd: widget.onAddSize,
          onRemove: widget.onRemoveSize,
        ),
      ],
    ),
  );
}
