import 'package:flutter/material.dart';

import '../../../domain/stroke.dart';
import '../../../ink/pen/pen_profile.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/app_theme.dart';
import 'option_controls.dart';
import 'stroke_preview.dart';

/// Options for the pen or highlighter: pen type, width, opacity, pressure
/// sensitivity, stabiliser, tapers and hold-to-straighten. Edits apply live.
class PenOptionsPanel extends StatelessWidget {
  const PenOptionsPanel({super.key, required this.tools, required this.ink});

  final ToolSettings tools;

  /// [InkTool.highlighter] or null for "the current pen type".
  final InkTool? ink;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tools,
      builder: (context, _) {
        final tool = ink ?? tools.penType;
        final config = tools.configOf(tool);
        final profile = PenProfile.of(tool);
        void update(PenConfig Function(PenConfig) f) => tools.updateConfig(tool, f);
        final isPen = !tool.isHighlighter;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OptionHeader(
              isPen ? 'Pen' : 'Highlighter',
              trailing: TextButton(
                onPressed: () => update((_) => PenConfig.defaultsFor(tool)),
                child: const Text('Reset'),
              ),
            ),
            if (isPen) ...[const SizedBox(height: Gaps.sm), _PenTypeGrid(tools: tools)],
            const SizedBox(height: Gaps.md),
            _PreviewCard(tool: tool, config: config),
            OptionSlider(
              label: 'Width',
              value: config.current.width,
              min: profile.minWidth,
              max: profile.maxWidth,
              display: (v) => v.toStringAsFixed(1),
              onChanged: (v) =>
                  update((c) => c.withPreset(c.selected, c.current.copyWith(width: v))),
            ),
            OptionSlider(
              label: 'Opacity',
              value: config.opacity,
              min: PenConfig.minOpacity,
              max: 1,
              display: percent,
              onChanged: (v) => update((c) => c.copyWith(opacity: v)),
            ),
            if (isPen)
              OptionSlider(
                label: 'Pressure sensitivity',
                value: config.thinning,
                min: 0,
                max: 1,
                display: percent,
                onChanged: (v) => update((c) => c.copyWith(thinning: v)),
              ),
            OptionSlider(
              label: 'Stabiliser',
              value: config.streamline,
              min: 0,
              max: 0.95,
              display: percent,
              onChanged: (v) => update((c) => c.copyWith(streamline: v)),
            ),
            if (isPen && profile.taperFactor > 0)
              OptionSwitch(
                label: 'Tapered ends',
                value: config.taper,
                onChanged: (v) => update((c) => c.copyWith(taper: v)),
              ),
            OptionSwitch(
              label: 'Hold to snap shapes',
              subtitle: 'Pause at the end of a stroke to make it a straight line or a clean shape',
              value: tools.holdToStraighten,
              onChanged: (v) => tools.holdToStraighten = v,
            ),
          ],
        );
      },
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.tool, required this.config});

  final InkTool tool;
  final PenConfig config;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gaps.md, vertical: Gaps.sm),
      decoration: BoxDecoration(
        // Ink is previewed on paper-white, as it will appear on the page.
        color: Palette.paper,
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: StrokePreview(tool: tool, config: config, height: 64),
    );
  }
}

/// The pen types as selectable tiles, each previewing its own ink.
class _PenTypeGrid extends StatelessWidget {
  const _PenTypeGrid({required this.tools});

  final ToolSettings tools;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (final type in InkTool.pens)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _PenTypeTile(
                tool: type,
                config: tools.configOf(type),
                selected: tools.penType == type,
                scheme: scheme,
                onTap: () => tools.penType = type,
              ),
            ),
          ),
      ],
    );
  }
}

class _PenTypeTile extends StatelessWidget {
  const _PenTypeTile({
    required this.tool,
    required this.config,
    required this.selected,
    required this.scheme,
    required this.onTap,
  });

  final InkTool tool;
  final PenConfig config;
  final bool selected;
  final ColorScheme scheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = PenProfile.of(tool).label;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? scheme.secondaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(Radii.control - 2),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.control - 2),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Palette.paper,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: StrokePreview(
                    tool: tool,
                    config: config,
                    width: PenProfile.of(tool).presets.first.width.clamp(2.0, 9.0),
                    height: 30,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
