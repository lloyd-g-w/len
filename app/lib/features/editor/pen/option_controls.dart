import 'package:flutter/material.dart';

import '../../../ui/app_theme.dart';

/// A labelled slider row used in the tool option panels.
class OptionSlider extends StatelessWidget {
  const OptionSlider({
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

  /// Formats the value shown at the end of the row.
  final String Function(double) display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: Gaps.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: text.labelLarge)),
              Text(display(value), style: text.labelMedium),
            ],
          ),
          SliderTheme(
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
        ],
      ),
    );
  }
}

/// A compact labelled switch row.
class OptionSwitch extends StatelessWidget {
  const OptionSwitch({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      visualDensity: VisualDensity.compact,
      title: Text(label, style: Theme.of(context).textTheme.labelLarge),
      subtitle: subtitle == null ? null : Text(subtitle!),
      value: value,
      onChanged: onChanged,
    );
  }
}

/// Section heading inside an option panel.
class OptionHeader extends StatelessWidget {
  const OptionHeader(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
        ?trailing,
      ],
    );
  }
}

String percent(double v) => '${(v * 100).round()}%';
