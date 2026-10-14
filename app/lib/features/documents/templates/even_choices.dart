import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/roving_focus.dart';

/// One option of [EvenChoices].
class EvenChoice {
  const EvenChoice({
    required this.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.leading,
  });

  final Key key;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// A small visual before the label (a colour swatch), [leadingSize] wide.
  final Widget? leading;
}

/// Choice chips of equal width in one row that fills the width — or two
/// even rows when they don't all fit (phones, large text), never a ragged
/// wrap. Paper colours and page formats in the template pickers.
class EvenChoices extends StatelessWidget {
  const EvenChoices({super.key, required this.choices});

  final List<EvenChoice> choices;

  static const double leadingSize = 18;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge;
    final scaler = MediaQuery.textScalerOf(context);
    var widest = 0.0;
    for (final c in choices) {
      final painter = TextPainter(
        text: TextSpan(text: c.label, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      final leading = c.leading == null ? 0 : leadingSize + Gaps.sm;
      widest = math.max(widest, painter.width + leading);
      painter.dispose();
    }
    final needed = widest + 2 * Gaps.md + 2;
    return LayoutBuilder(
      builder: (context, constraints) {
        final n = choices.length;
        final perRow = constraints.maxWidth >= n * needed + (n - 1) * Gaps.sm ? n : (n + 1) ~/ 2;
        // One Tab stop, at the chosen option; the arrows move inside.
        return RovingGroup.grid(
          child: Column(
            children: [
              for (var r = 0; r < n; r += perRow)
                Padding(
                  padding: EdgeInsets.only(top: r == 0 ? 0 : Gaps.sm),
                  child: Row(
                    children: [
                      for (var i = r; i < r + perRow; i++) ...[
                        if (i > r) const SizedBox(width: Gaps.sm),
                        Expanded(child: i < n ? _Chip(choices[i]) : const SizedBox()),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// A full-width choice chip, content centred; styled like the theme's
/// `ChoiceChip`s (a Rule edge; selected, an Ink plate).
class _Chip extends StatelessWidget {
  const _Chip(this.choice);

  final EvenChoice choice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(Radii.sm);
    final selected = choice.selected;
    return RovingItem(
      stop: selected,
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          key: choice.key,
          color: selected ? Surfaces.pressed(scheme) : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: selected ? Colors.transparent : scheme.outlineVariant),
          ),
          child: InkWell(
            onTap: choice.onTap,
            borderRadius: radius,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gaps.md, vertical: Gaps.xs),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (choice.leading case final leading?) ...[
                      SizedBox.square(dimension: EvenChoices.leadingSize, child: leading),
                      const SizedBox(width: Gaps.sm),
                    ],
                    Flexible(
                      child: Text(
                        choice.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
