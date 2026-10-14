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
import 'size_scale.dart';
import 'stroke_preview.dart';

/// The pen's or highlighter's section of the tool options popover: a title
/// with Reset (as every tool popover has: it puts the feel back to its
/// defaults), a live preview, the colour and size of the selected quick
/// slots, the ink's own panel ([feel]: pressure, stabiliser… ) collapsed
/// under [feelLabel], and, collapsed under "Quick colours and sizes", how
/// many of each the toolbar shows. Edits apply live. Nothing resets the
/// quick colours and sizes: they are the user's choices.
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
  /// Whether Feel and Quick colours and sizes are open; remembered while the app runs.
  static bool _feelOpen = false;
  static bool _slotsOpen = false;

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
        final scale = SizeScale(PenDefaults.of(ink));
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OptionHeader(
              widget.title,
              trailing: ResetButton<PenConfig>(
                value: config,
                defaults: config.withFeelDefaults(ink),
                onChanged: (c) => _update((_) => c),
              ),
            ),
            const SizedBox(height: Gaps.sm),
            PreviewCard(tool: ink, config: config),
            if (popoverIsSheet(context)) ...[
              const SizedBox(height: Gaps.sm),
              Row(
                children: [
                  ColorSlots(tools: tools, ink: ink, editable: false),
                  const Spacer(),
                  WidthSlots(tools: tools, ink: ink, editable: false),
                ],
              ),
            ],
            const SizedBox(height: Gaps.sm),
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
            OptionDisclosure(
              label: 'Quick colours and sizes',
              summary: '${config.colors.length} and ${config.widths.length}',
              open: _slotsOpen,
              onToggle: () => setState(() => _slotsOpen = !_slotsOpen),
              child: Column(
                children: [
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
              ),
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
