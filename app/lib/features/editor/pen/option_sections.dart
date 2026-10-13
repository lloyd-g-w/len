import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_theme.dart';

/// A collapsible section: its label and a chevron, then [child] when open.
class OptionDisclosure extends StatelessWidget {
  const OptionDisclosure({
    super.key,
    required this.label,
    required this.open,
    required this.onToggle,
    required this.child,
  });

  final String label;
  final bool open;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: theme.colorScheme.outlineVariant),
        Semantics(
          button: true,
          expanded: open,
          child: InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(Radii.sm),
            child: SizedBox(
              height: Targets.menuRow,
              child: Row(
                children: [
                  Expanded(child: Text(label, style: theme.textTheme.labelLarge)),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: Motion.fast,
                    child: Icon(
                      Symbols.expand_more_rounded,
                      size: Glyphs.bar,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: Motion.fast,
          curve: Motion.standard,
          alignment: Alignment.topCenter,
          child: open ? child : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

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
        Expanded(child: Text('Quick $noun', style: text.labelLarge)),
        step(Symbols.remove_rounded, 'Fewer quick $noun', count > min ? onRemove : null),
        SizedBox(
          width: Gaps.xl,
          child: Text(
            '$count',
            textAlign: TextAlign.center,
            semanticsLabel: '$count quick $noun',
            style: text.labelLarge?.copyWith(fontFeatures: AppTheme.tabularFigures),
          ),
        ),
        step(Symbols.add_rounded, 'More quick $noun', count < max ? onAdd : null),
      ],
    );
  }
}
