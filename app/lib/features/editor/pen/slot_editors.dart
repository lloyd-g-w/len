import 'package:flutter/material.dart';

import '../../../domain/stroke.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/adaptive_popover.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/color_picker/color_picker.dart';
import 'option_controls.dart';
import 'stroke_preview.dart';

/// Selects colour slot [index] of [ink] and opens its editor at [anchor].
Future<void> openColorSlotEditor(BuildContext anchor, ToolSettings tools, InkTool ink, int index) {
  tools.selectColor(index);
  return showAdaptivePopover<void>(
    context: anchor,
    builder: (_) => ColorSlotEditor(tools: tools, ink: ink, index: index),
  );
}

/// Selects width slot [index] of [ink] and opens its editor at [anchor].
Future<void> openWidthSlotEditor(BuildContext anchor, ToolSettings tools, InkTool ink, int index) {
  tools.selectWidth(index);
  return showAdaptivePopover<void>(
    context: anchor,
    width: 300,
    builder: (_) => WidthSlotEditor(tools: tools, ink: ink, index: index),
  );
}

/// Changes one quick colour with the full colour picker (applies live).
class ColorSlotEditor extends StatelessWidget {
  const ColorSlotEditor({super.key, required this.tools, required this.ink, required this.index});

  final ToolSettings tools;
  final InkTool ink;
  final int index;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tools,
      builder: (context, _) {
        final config = tools.configOf(ink);
        if (index >= config.colors.length) return const SizedBox.shrink();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _EditorHeader(
              title: 'Colour ${index + 1}',
              canRemove: config.colors.length > PenConfig.minSlots,
              removeLabel: 'Remove colour',
              onRemove: () => tools.updateConfig(ink, (c) => c.removeColor(index)),
            ),
            const SizedBox(height: Gaps.sm),
            ColorPicker(
              color: config.colors[index],
              showOpacity: false,
              favorites: tools.favorites,
              onAddFavorite: tools.addFavorite,
              onRemoveFavorite: tools.removeFavorite,
              onChanged: (c) => tools.updateConfig(
                ink,
                (cfg) => cfg.withColor(index, c).copyWith(colorIndex: index),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Changes one quick width with a slider and a live stroke preview.
class WidthSlotEditor extends StatelessWidget {
  const WidthSlotEditor({super.key, required this.tools, required this.ink, required this.index});

  final ToolSettings tools;
  final InkTool ink;
  final int index;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tools,
      builder: (context, _) {
        final config = tools.configOf(ink);
        if (index >= config.widths.length) return const SizedBox.shrink();
        final defaults = PenDefaults.of(ink);
        final width = config.widths[index];
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _EditorHeader(
              title: 'Width ${index + 1}',
              canRemove: config.widths.length > PenConfig.minSlots,
              removeLabel: 'Remove width',
              onRemove: () => tools.updateConfig(ink, (c) => c.removeWidth(index)),
            ),
            const SizedBox(height: Gaps.sm),
            PreviewCard(tool: ink, config: config, width: width),
            OptionSlider(
              label: 'Width',
              value: width,
              min: defaults.minWidth,
              max: defaults.maxWidth,
              display: (v) => v.toStringAsFixed(v < 10 ? 1 : 0),
              onChanged: (w) => tools.updateConfig(
                ink,
                (c) =>
                    c.withWidth(index, (w * 10).roundToDouble() / 10).copyWith(widthIndex: index),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Title row with a remove action that also closes the editor.
class _EditorHeader extends StatelessWidget {
  const _EditorHeader({
    required this.title,
    required this.canRemove,
    required this.removeLabel,
    required this.onRemove,
  });

  final String title;
  final bool canRemove;
  final String removeLabel;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return OptionHeader(
      title,
      trailing: IconButton(
        tooltip: canRemove ? removeLabel : 'At least one is needed',
        onPressed: canRemove
            ? () {
                Navigator.of(context).maybePop();
                onRemove();
              }
            : null,
        icon: const Icon(Icons.delete_outline_rounded),
      ),
    );
  }
}
