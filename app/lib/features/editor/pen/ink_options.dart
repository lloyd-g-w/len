import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/stroke.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/color_dot.dart';
import '../../../ui/color_picker/color_picker.dart';
import '../../../ui/color_picker/color_swatches.dart';
import '../../../ui/section_label.dart';
import 'ink_slots.dart';
import 'option_controls.dart';
import 'stroke_preview.dart';

/// The pen's or highlighter's section of the tool options popover: a live
/// preview, the colour of the selected quick colour (palette, recent
/// colours, custom), the selected quick width, how many quick colours and
/// widths there are (1–6 each), and the ink's own panel ([feel]: pressure,
/// stabiliser… ) collapsed under [feelLabel]. Edits apply live.
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

  /// Whether the custom colour picker is open.
  bool _custom = false;

  ToolSettings get tools => widget.tools;
  InkTool get ink => widget.ink;

  void _update(PenConfig Function(PenConfig) f) => tools.updateConfig(ink, f);

  void _setColor(int argb) => _update((c) => c.withColor(c.colorIndex, argb | 0xFF000000));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tools,
      builder: (context, _) {
        final config = tools.configOf(ink);
        final defaults = PenDefaults.of(ink);
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
            const SizedBox(height: Gaps.md),
            _SlotsHeader(
              label: 'Colour',
              noun: 'colours',
              count: config.colors.length,
              onAdd: () => _update((c) => c.addColor(_unusedColor(c.colors))),
              onRemove: () => _update((c) => c.removeColor(c.colors.length - 1)),
            ),
            ColorSlots(tools: tools, ink: ink),
            const SizedBox(height: Gaps.sm),
            _Palette(
              selected: config.color,
              recent: tools.recentColors,
              custom: _custom,
              onPick: _setColor,
              onCustom: () => setState(() => _custom = !_custom),
            ),
            if (_custom) ...[
              const SizedBox(height: Gaps.md),
              ColorPicker(
                color: config.color,
                showOpacity: false,
                showSwatches: false,
                onChanged: _setColor,
              ),
            ],
            const SizedBox(height: Gaps.md),
            _SlotsHeader(
              label: 'Width',
              noun: 'widths',
              count: config.widths.length,
              onAdd: () => _update((c) => c.addWidth(_newWidth(c))),
              onRemove: () => _update((c) => c.removeWidth(c.widths.length - 1)),
            ),
            WidthSlots(tools: tools, ink: ink),
            OptionSlider(
              label: 'Width ${config.widthIndex + 1}',
              value: config.width,
              min: defaults.minWidth,
              max: defaults.maxWidth,
              display: formatWidth,
              onChanged: (w) =>
                  _update((c) => c.withWidth(c.widthIndex, (w * 10).roundToDouble() / 10)),
            ),
            const SizedBox(height: Gaps.sm),
            _Disclosure(
              label: widget.feelLabel,
              open: _feelOpen,
              onToggle: () => setState(() => _feelOpen = !_feelOpen),
              child: EmbeddedOptions(child: widget.feel),
            ),
          ],
        );
      },
    );
  }

  /// A palette colour not in the row yet, to start a new slot with.
  static int _unusedColor(List<int> used) => ColorSwatches.palette.firstWhere(
    (c) => !used.contains(c) && c != 0xFFFFFFFF,
    orElse: () => ColorSwatches.palette.first,
  );

  /// A width for a new slot: a step above the current one, or below it
  /// when that would exceed the range.
  double _newWidth(PenConfig c) {
    final d = PenDefaults.of(ink);
    final up = c.widths.last * 1.5;
    return d.clampWidth(up <= d.maxWidth ? up : c.width / 1.5);
  }
}

/// "Colour" or "Width", with − n + to set how many quick slots there are.
class _SlotsHeader extends StatelessWidget {
  const _SlotsHeader({
    required this.label,
    required this.noun,
    required this.count,
    required this.onAdd,
    required this.onRemove,
  });

  final String label;

  /// Plural, for the tooltips ("colours").
  final String noun;
  final int count;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget step(IconData icon, String tooltip, VoidCallback? onPressed) => IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: Glyphs.menu,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon),
    );
    return Row(
      children: [
        Expanded(child: Text(label, style: theme.textTheme.labelLarge)),
        step(
          Symbols.remove_rounded,
          'Fewer quick $noun',
          count > PenConfig.minSlots ? onRemove : null,
        ),
        SizedBox(
          width: 20,
          child: Text(
            '$count',
            textAlign: TextAlign.center,
            semanticsLabel: '$count quick $noun',
            style: theme.textTheme.labelLarge?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        step(Symbols.add_rounded, 'More quick $noun', count < PenConfig.maxSlots ? onAdd : null),
      ],
    );
  }
}

/// The preset palette, then the recent colours and Custom.
class _Palette extends StatelessWidget {
  const _Palette({
    required this.selected,
    required this.recent,
    required this.custom,
    required this.onPick,
    required this.onCustom,
  });

  final int selected;
  final List<int> recent;

  /// Whether the custom picker is open.
  final bool custom;
  final ValueChanged<int> onPick;
  final VoidCallback onCustom;

  static const int _columns = 10;
  static const double _gap = 4;

  @override
  Widget build(BuildContext context) {
    final selected = this.selected | 0xFF000000;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = ((constraints.maxWidth - _gap * (_columns - 1)) / _columns).clamp(20.0, 32.0);
        Widget dot(int c) =>
            ColorDot(color: c, size: size, selected: c == selected, onTap: () => onPick(c));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: _gap,
              runSpacing: _gap,
              children: [for (final c in ColorSwatches.palette) dot(c)],
            ),
            const SizedBox(height: Gaps.sm),
            Row(
              children: [
                if (recent.isNotEmpty) ...[
                  const SectionLabel('Recent'),
                  const SizedBox(width: Gaps.sm),
                  Expanded(
                    child: Wrap(spacing: _gap, children: [for (final c in recent.take(6)) dot(c)]),
                  ),
                ] else
                  const Spacer(),
                TextButton.icon(
                  onPressed: onCustom,
                  icon: Icon(
                    custom ? Symbols.expand_less_rounded : Symbols.palette_rounded,
                    size: Glyphs.menu,
                  ),
                  label: const Text('Custom'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// A collapsible section: its label and a chevron, then [child] when open.
class _Disclosure extends StatelessWidget {
  const _Disclosure({
    required this.label,
    required this.open,
    required this.onToggle,
    required this.child,
  });

  final String label;
  final bool open;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: theme.colorScheme.outlineVariant),
        Semantics(
          button: true,
          expanded: open,
          child: InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(Radii.sm),
            child: SizedBox(
              height: Targets.menuRow,
              child: Row(
                children: [
                  Expanded(child: Text(label, style: theme.textTheme.labelLarge)),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: Motion.fast,
                    child: Icon(
                      Symbols.expand_more_rounded,
                      size: Glyphs.bar,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: Motion.fast,
          curve: Motion.standard,
          alignment: Alignment.topCenter,
          child: open ? child : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
