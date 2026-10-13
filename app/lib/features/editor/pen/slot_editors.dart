import 'package:flutter/material.dart';

import '../../../domain/stroke.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/adaptive_popover.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/color_picker/color_choices.dart';
import '../../../ui/color_picker/color_swatches.dart';
import '../toolbar/tool_options_popover.dart';
import 'ink_paper.dart';
import 'ink_slots.dart';
import 'option_controls.dart';
import 'size_scale.dart';
import 'stroke_preview.dart';

/// Opens the small editor of quick colour [index] of [ink] at [anchor] (the
/// slot): the palette, recent colours and Custom, changing that slot's
/// colour live. Anchored on tablets and desktops, a compact sheet on
/// phones. A colour new to the slot becomes a recent one when it closes.
Future<void> editColorSlot(
  BuildContext anchor, {
  required ToolSettings tools,
  required InkTool ink,
  required int index,
}) async {
  final before = tools.configOf(ink).colors[index];
  await showAdaptivePopover<void>(
    context: anchor,
    width: Targets.touchFirst ? toolOptionsTouchWidth : popoverWidth,
    builder: (_) => ColorSlotEditor(tools: tools, ink: ink, index: index),
  );
  final colors = tools.configOf(ink).colors;
  if (index < colors.length && colors[index] != before) tools.addRecentColor(colors[index]);
}

/// Opens the small editor of quick size [index] of [ink] at [anchor] (the
/// slot): a size slider (millimetres, log scale) with a live preview in
/// the ink's colour. Anchored on tablets and desktops, a compact sheet on
/// phones.
Future<void> editWidthSlot(
  BuildContext anchor, {
  required ToolSettings tools,
  required InkTool ink,
  required int index,
}) => showAdaptivePopover<void>(
  context: anchor,
  width: WidthSlotEditor.width,
  builder: InkPaper.carry(anchor, (_) => WidthSlotEditor(tools: tools, ink: ink, index: index)),
);

/// The colour of one quick slot: palette, recent colours and Custom.
class ColorSlotEditor extends StatelessWidget {
  const ColorSlotEditor({super.key, required this.tools, required this.ink, required this.index});

  final ToolSettings tools;
  final InkTool ink;
  final int index;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: tools,
    builder: (context, _) {
      final colors = tools.configOf(ink).colors;
      if (index >= colors.length) return const SizedBox.shrink();
      return KeyedSubtree(
        key: const ValueKey('color-slot-editor'),
        child: ColorChoices(
          color: colors[index],
          palette: ink.isHighlighter ? ColorSwatches.highlighter : ColorSwatches.palette,
          recent: tools.recentColors,
          onChanged: (argb) => tools.updateConfig(ink, (c) => c.withColor(index, argb)),
        ),
      );
    },
  );
}

/// The size of one quick slot: a live preview, then the slider.
class WidthSlotEditor extends StatelessWidget {
  const WidthSlotEditor({super.key, required this.tools, required this.ink, required this.index});

  final ToolSettings tools;
  final InkTool ink;
  final int index;

  /// The anchored popover's width.
  static const double width = 288;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: tools,
    builder: (context, _) {
      final config = tools.configOf(ink);
      if (index >= config.widths.length) return const SizedBox.shrink();
      final scale = SizeScale(PenDefaults.of(ink));
      return Column(
        key: const ValueKey('width-slot-editor'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PreviewCard(
            tool: ink,
            config: config,
            width: config.widths[index],
            height: 56,
            sample: PreviewSample.line,
          ),
          const SizedBox(height: Gaps.xs),
          OptionSlider(
            label: 'Size',
            value: scale.toSlider(config.widths[index]),
            min: 0,
            max: 1,
            display: (t) => formatWidth(scale.toWidth(t)),
            onChanged: (t) => tools.updateConfig(ink, (c) => c.withWidth(index, scale.toWidth(t))),
          ),
        ],
      );
    },
  );
}
