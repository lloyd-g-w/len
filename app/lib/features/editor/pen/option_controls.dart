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
    this.hint,
  });

  final String label;

  /// A one-line explanation under the slider.
  final String? hint;
  final double value;
  final double min;
  final double max;

  /// Formats the value shown at the end of the row.
  final String Function(double) display;

  /// Null disables the slider.
  final ValueChanged<double>? onChanged;

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
          if (hint case final hint?)
            Text(
              hint,
              style: text.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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

  /// Null disables the switch.
  final ValueChanged<bool>? onChanged;

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

/// The stabiliser (`PenConfig.streamline`) slider: "Off" at 0, else a
/// percentage, with a hint about its trade-off.
class StabiliserSlider extends StatelessWidget {
  const StabiliserSlider({super.key, required this.value, required this.onChanged});

  final double value;

  /// Null disables the slider (e.g. for straight lines, which it does not
  /// affect).
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) => OptionSlider(
    label: 'Stabiliser',
    hint: 'Smooths shaky lines; the ink trails the pen a little',
    value: value,
    min: 0,
    max: 1,
    display: (v) => v == 0 ? 'Off' : percent(v),
    // The low end snaps to off: a barely-on stabiliser would still lag.
    onChanged: switch (onChanged) {
      final onChanged? => (v) => onChanged(v < 0.01 ? 0 : v),
      null => null,
    },
  );
}

/// An ink settings popover's title row with Reset (restores the feel defaults).
class FeelHeader extends StatelessWidget {
  const FeelHeader(this.title, {super.key, required this.onReset});

  final String title;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) => OptionHeader(
    title,
    trailing: TextButton(onPressed: onReset, child: const Text('Reset')),
  );
}
