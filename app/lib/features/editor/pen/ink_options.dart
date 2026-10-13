import 'package:flutter/material.dart';

import '../../../domain/stroke.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/adaptive_popover.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/color_picker/color_choices.dart';
import '../../../ui/color_picker/color_swatches.dart';
import '../../../ui/group_header.dart';
import 'ink_slots.dart';
import 'option_controls.dart';
import 'option_sections.dart';
import 'size_scale.dart';
import 'stroke_preview.dart';

/// The pen's or highlighter's section of the tool options popover: a live
/// preview, the colour and size of the selected quick slots, the ink's own
/// panel ([feel]: pressure, stabiliser… ) collapsed under [feelLabel] with
/// "Reset feel" at its end (then any [gestures]), and, collapsed under Toolbar, how many quick
/// colours and sizes the toolbar shows. Edits apply live. Nothing resets
/// the quick colours and sizes: they are the user's choices.
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
    this.gestures,
  });

  final ToolSettings tools;
  final InkTool ink;
  final String title;
  final String feelLabel;

  /// The ink's options panel, hosted as is (its title and preview step
  /// aside, see [EmbeddedOptions]).
  final Widget feel;

  /// Global switches shown at the end of the Feel section, after "Reset
  /// feel" (which doesn't touch them): the pen's [PenGestures].
  final Widget? gestures;

  @override
  State<InkOptions> createState() => _InkOptionsState();
}

class _InkOptionsState extends State<InkOptions> {
  /// Whether Feel and Toolbar are open; remembered while the app runs.
  static bool _feelOpen = false;
  static bool _toolbarOpen = false;

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
            OptionHeader(widget.title),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  EmbeddedOptions(child: widget.feel),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: _ResetFeel(config: config, ink: ink, onReset: (c) => _update((_) => c)),
                  ),
                  ?widget.gestures,
                ],
              ),
            ),
            OptionDisclosure(
              label: 'Toolbar',
              summary:
                  '${_count(config.colors.length, 'colour')}, '
                  '${_count(config.widths.length, 'size')}',
              open: _toolbarOpen,
              onToggle: () => setState(() => _toolbarOpen = !_toolbarOpen),
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

  static String _count(int n, String noun) => n == 1 ? '1 $noun' : '$n ${noun}s';

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

/// "Reset feel": puts the ink's feel (pressure, stabiliser, ends, opacity…)
/// back to its defaults, keeping the quick colours and sizes. Disabled at
/// the defaults. It needs no Undo: what it changes is right above it.
class _ResetFeel extends StatelessWidget {
  const _ResetFeel({required this.config, required this.ink, required this.onReset});

  final PenConfig config;
  final InkTool ink;
  final ValueChanged<PenConfig> onReset;

  @override
  Widget build(BuildContext context) {
    final defaults = config.withFeelDefaults(ink);
    return EndTextButton(
      onPressed: config == defaults ? null : () => onReset(defaults),
      label: 'Reset feel',
    );
  }
}
