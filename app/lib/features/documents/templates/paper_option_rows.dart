import 'package:flutter/material.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/chip_surface.dart';

/// A labelled row: the label in a fixed column, the control beside it.
class PaperOptionRow extends StatelessWidget {
  const PaperOptionRow({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  static const double labelWidth = 64;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gaps.xxs),
      child: Row(
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// A one-line slider: label, slider, value.
class PaperSliderRow extends StatelessWidget {
  const PaperSliderRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String Function(double) display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        SizedBox(
          width: PaperOptionRow.labelWidth,
          child: Text(label, style: text.labelLarge),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context)
                .copyWith(overlayShape: const RoundSliderOverlayShape(overlayRadius: 14)),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
              semanticFormatterCallback: display,
            ),
          ),
        ),
        SizedBox(
          width: 56,
          child: Text(display(value), style: text.labelMedium, textAlign: TextAlign.end),
        ),
      ],
    );
  }
}

/// A row of colour swatches, the custom colour last: one line always,
/// scaled down a little where it would otherwise wrap one swatch alone
/// (a narrow side panel).
class SwatchWrap extends StatelessWidget {
  const SwatchWrap({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: AlignmentDirectional.centerStart,
    child: Row(mainAxisSize: MainAxisSize.min, spacing: Gaps.xs, children: children),
  );
}

class PaperExtraChip extends StatelessWidget {
  const PaperExtraChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) => ChipSurface(
    child: FilterChip(
      label: Text(label),
      selected: selected,
      visualDensity: VisualDensity.compact,
      onSelected: onSelected,
    ),
  );
}
