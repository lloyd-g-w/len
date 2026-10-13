import 'package:flutter/material.dart';

import '../../../domain/stroke.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/app_switch.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/group_header.dart';

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
    this.showValue = true,
  });

  final String label;

  /// Whether the value shows at the end of the row (it is still read out);
  /// false for sizes on screen, which a preview shows better than a number.
  final bool showValue;

  static const double _overlay = 14;

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
    final theme = Theme.of(context);
    final text = theme.textTheme;
    // Labels fade with a disabled slider, like a disabled switch's.
    final faded = onChanged == null ? theme.colorScheme.onSurface.withValues(alpha: 0.38) : null;
    return Padding(
      padding: const EdgeInsets.only(top: Gaps.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GroupHeader(label, value: showValue ? display(value) : null, enabled: onChanged != null),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              overlayShape: const RoundSliderOverlayShape(overlayRadius: _overlay),
              // The track lines up with the label above it.
              padding: const EdgeInsets.symmetric(horizontal: Gaps.sm, vertical: Gaps.md),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
              semanticFormatterCallback: display,
            ),
          ),
          // As far from the next group as the slider's own end is.
          if (hint case final hint?)
            Padding(
              padding: const EdgeInsets.only(bottom: Gaps.sm),
              child: Text(
                hint,
                style: text.bodySmall?.copyWith(color: faded ?? theme.colorScheme.onSurfaceVariant),
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
    return AppSwitchTile(
      padding: EdgeInsets.zero,
      title: label,
      titleStyle: Theme.of(context).textTheme.labelLarge,
      subtitle: subtitle,
      value: value,
      onChanged: onChanged,
    );
  }
}

/// The hairline between groups of an options popover (DESIGN §6: groups
/// are separated by a rule, not by spacing alone).
class OptionRule extends StatelessWidget {
  const OptionRule({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Gaps.sm),
    child: Divider(
      height: Hairline.width,
      thickness: Hairline.width,
      color: Theme.of(context).colorScheme.outlineVariant,
    ),
  );
}

/// Section heading inside an option panel.
class OptionHeader extends StatelessWidget {
  const OptionHeader(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    // One height with or without a button, so the title never moves.
    return SizedBox(
      height: EndTextButton.height,
      child: Row(
        children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
          ?trailing,
        ],
      ),
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

/// An ink settings panel's title row with Reset (restores the feel
/// defaults). Inside an [EmbeddedOptions] (the options popover's Feel
/// section, whose header resets everything) it shows nothing.
class FeelHeader extends StatelessWidget {
  const FeelHeader(this.title, {super.key, required this.tools, required this.ink});

  final String title;
  final ToolSettings tools;
  final InkTool ink;

  @override
  Widget build(BuildContext context) {
    if (EmbeddedOptions.of(context)) return const SizedBox.shrink();
    final config = tools.configOf(ink);
    return OptionHeader(
      title,
      trailing: ResetButton<PenConfig>(
        value: config,
        defaults: config.withFeelDefaults(ink),
        onChanged: (c) => tools.updateConfig(ink, (_) => c),
      ),
    );
  }
}

/// An options popover's Reset: puts every setting the popover shows back
/// to [defaults]. Until something else changes it then reads Undo, which
/// puts back what was there. Disabled while the settings are the defaults.
class ResetButton<T extends Object> extends StatefulWidget {
  const ResetButton({
    super.key,
    required this.value,
    required this.defaults,
    required this.onChanged,
  });

  /// The settings now.
  final T value;
  final T defaults;
  final ValueChanged<T> onChanged;

  @override
  State<ResetButton<T>> createState() => _ResetButtonState<T>();
}

class _ResetButtonState<T extends Object> extends State<ResetButton<T>> {
  /// The settings before Reset, while Undo is offered.
  T? _before;

  @override
  void didUpdateWidget(ResetButton<T> old) {
    super.didUpdateWidget(old);
    // Another change since Reset: Undo would throw it away.
    if (widget.value != widget.defaults) _before = null;
  }

  @override
  Widget build(BuildContext context) {
    final before = _before;
    if (before != null) {
      return EndTextButton(
        onPressed: () {
          setState(() => _before = null);
          widget.onChanged(before);
        },
        label: 'Undo',
      );
    }
    final atDefaults = widget.value == widget.defaults;
    return EndTextButton(
      onPressed: atDefaults
          ? null
          : () {
              setState(() => _before = widget.value);
              widget.onChanged(widget.defaults);
            },
      label: 'Reset',
    );
  }
}

/// Marks an options panel as hosted inside the tool options popover, which
/// shows the title, Reset and the stroke preview itself: [FeelHeader] and
/// `PreviewCard` then step aside. This lets the popover wrap the pen and
/// highlighter panels without changing them.
class EmbeddedOptions extends InheritedWidget {
  const EmbeddedOptions({super.key, required super.child});

  /// Whether [context] is inside an [EmbeddedOptions].
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<EmbeddedOptions>() != null;

  @override
  bool updateShouldNotify(EmbeddedOptions oldWidget) => false;
}
