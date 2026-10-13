import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/stroke.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/adaptive_popover.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/color_picker/color_choices.dart';
import '../../../ui/color_picker/color_swatches.dart';
import 'ink_slots.dart';
import 'option_controls.dart';
import 'option_sections.dart';
import 'stroke_preview.dart';

/// The pen's or highlighter's section of the tool options popover: a live
/// preview, the colour and size of the selected quick slots, the ink's own
/// panel ([feel]: pressure, stabiliser… ) collapsed under [feelLabel], and
/// how many quick colours and sizes the toolbar shows. Edits apply live.
///
/// The quick slots themselves show here only in the phone sheet, which
/// covers the toolbar; the anchored popover sits right under them.
class InkOptions extends StatefulWidget {
  const InkOptions({
    super.key,
    required this.tools,
    required this.ink,
    required this.title,
    required this.feelLabel,
    required this.feel,
  });

  final ToolSettings tools;
  final InkTool ink;
  final String title;
  final String feelLabel;

  /// The ink's options panel, hosted as is (its title and preview step
  /// aside, see [EmbeddedOptions]).
  final Widget feel;

  @override
  State<InkOptions> createState() => _InkOptionsState();
}

class _InkOptionsState extends State<InkOptions> {
  /// Whether Feel is open; remembered while the app runs.
  static bool _feelOpen = false;

  ToolSettings get tools => widget.tools;
  InkTool get ink => widget.ink;
  List<int> get _palette => ink.isHighlighter ? ColorSwatches.highlighter : ColorSwatches.palette;

  void _update(PenConfig Function(PenConfig) f) => tools.updateConfig(ink, f);

  void _setColor(int argb) => _update((c) => c.withColor(c.colorIndex, argb | 0xFF000000));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tools,
      builder: (context, _) {
        final config = tools.configOf(ink);
        final scale = _SizeScale(PenDefaults.of(ink));
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OptionHeader(
              widget.title,
              trailing: TextButton(
                onPressed: () => _update((c) => c.withFeelDefaults(ink)),
                child: const Text('Reset'),
              ),
            ),
            const SizedBox(height: Gaps.sm),
            PreviewCard(tool: ink, config: config),
            if (popoverIsSheet(context)) ...[
              const SizedBox(height: Gaps.sm),
              Row(
                children: [
                  ColorSlots(tools: tools, ink: ink),
                  const Spacer(),
                  WidthSlots(tools: tools, ink: ink),
                ],
              ),
            ],
            const SizedBox(height: Gaps.md),
            ColorChoices(
              color: config.color,
              palette: _palette,
              recent: tools.recentColors,
              onChanged: _setColor,
            ),
            const SizedBox(height: Gaps.sm),
            OptionSlider(
              label: 'Size',
              value: scale.toSlider(config.width),
              min: 0,
              max: 1,
              display: (t) => formatWidth(scale.toWidth(t)),
              onChanged: (t) => _update((c) => c.withWidth(c.widthIndex, scale.toWidth(t))),
            ),
            const SizedBox(height: Gaps.sm),
            OptionDisclosure(
              label: widget.feelLabel,
              open: _feelOpen,
              onToggle: () => setState(() => _feelOpen = !_feelOpen),
              child: EmbeddedOptions(child: widget.feel),
            ),
            Divider(height: Gaps.lg, color: Theme.of(context).colorScheme.outlineVariant),
            SlotCountRow(
              noun: 'colours',
              count: config.colors.length,
              min: PenConfig.minSlots,
              max: PenConfig.maxSlots,
              onAdd: () => _update((c) => c.addColor(_unusedColor(c.colors))),
              onRemove: () => _update((c) => c.removeColor(c.colors.length - 1)),
            ),
            SlotCountRow(
              noun: 'sizes',
              count: config.widths.length,
              min: PenConfig.minSlots,
              max: PenConfig.maxSlots,
              onAdd: () => _update((c) => c.addWidth(_newWidth(c))),
              onRemove: () => _update((c) => c.removeWidth(c.widths.length - 1)),
            ),
          ],
        );
      },
    );
  }

  /// A palette colour not in the row yet, to start a new slot with.
  int _unusedColor(List<int> used) => _palette.firstWhere(
    (c) => !used.contains(c) && c != 0xFFFFFFFF,
    orElse: () => _palette.first,
  );

  /// A width for a new slot: a step above the current one, or below it
  /// when that would exceed the range.
  double _newWidth(PenConfig c) {
    final d = PenDefaults.of(ink);
    final up = c.widths.last * 1.5;
    return d.clampWidth(up <= d.maxWidth ? up : c.width / 1.5);
  }
}

/// The size slider's scale: logarithmic, so fine pens get as much travel
/// as broad ones (the default sizes sit near the middle). Widths snap to
/// 0.1 world units.
class _SizeScale {
  _SizeScale(PenDefaults d) : _min = d.minWidth, _max = d.maxWidth;

  final double _min, _max;

  double get _span => math.log(_max / _min);

  double toSlider(double width) => math.log(width.clamp(_min, _max) / _min) / _span;

  double toWidth(double t) =>
      (_min * math.exp(t * _span) * 10).roundToDouble().clamp(_min * 10, _max * 10) / 10;
}
