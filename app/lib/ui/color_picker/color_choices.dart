import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../app_theme.dart';
import '../color_dot.dart';
import '../even_grid.dart';
import '../section_label.dart';
import 'color_picker.dart';
import 'color_swatches.dart';

/// The colour block every tool popover shares: a "Colour" heading with
/// Custom (opens the full picker in place), a [palette] (up to ten per
/// row), then the [recent] colours. Every pick applies at once through [onChanged] (opaque ARGB).
class ColorChoices extends StatefulWidget {
  const ColorChoices({
    super.key,
    required this.color,
    required this.onChanged,
    this.palette = ColorSwatches.palette,
    this.recent = const [],
  });

  /// The current colour (ARGB; its alpha is ignored).
  final int color;
  final ValueChanged<int> onChanged;
  final List<int> palette;

  /// Colours picked recently, most recent first; up to six show.
  final List<int> recent;

  @override
  State<ColorChoices> createState() => _ColorChoicesState();
}

class _ColorChoicesState extends State<ColorChoices> {
  /// Whether the custom picker is open.
  bool _customOpen = false;

  static const int _columns = 10;
  static const double _gap = 4;

  void _pick(int argb) => widget.onChanged(argb | 0xFF000000);

  @override
  Widget build(BuildContext context) {
    final selected = widget.color | 0xFF000000;
    final recent = [
      for (final c in widget.recent.take(6))
        if (!widget.palette.contains(c | 0xFF000000)) c | 0xFF000000,
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = ((constraints.maxWidth - _gap * (_columns - 1)) / _columns).clamp(20.0, 32.0);
        // On touch the swatches get 48-dp cells (fewer per row, EvenGrid).
        final visual = Targets.touchFirst ? 32.0 : size;
        Widget grid(List<int> colours) => EvenGrid(
          itemExtent: size,
          minSpacing: _gap,
          runSpacing: _gap,
          maxSpacing: _gap,
          touchTargets: true,
          children: [
            for (final c in colours)
              ColorDot(color: c, size: visual, selected: c == selected, onTap: () => _pick(c)),
          ],
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(child: SectionLabel('Colour')),
                TextButton.icon(
                  onPressed: () => setState(() => _customOpen = !_customOpen),
                  // Compact with a pointer; a full 48-dp target on touch.
                  style: TextButton.styleFrom(
                    visualDensity: Targets.touchFirst ? null : VisualDensity.compact,
                  ),
                  icon: Icon(
                    _customOpen ? Symbols.expand_less_rounded : Symbols.palette_rounded,
                    size: Glyphs.menu,
                  ),
                  label: const Text('Custom'),
                ),
              ],
            ),
            grid(widget.palette),
            if (recent.isNotEmpty) ...[
              const SizedBox(height: Gaps.sm),
              const SectionLabel('Recent'),
              const SizedBox(height: Gaps.xs),
              grid(recent),
            ],
            AnimatedSize(
              duration: Motion.fast,
              curve: Motion.standard,
              alignment: Alignment.topCenter,
              child: _customOpen
                  ? Padding(
                      padding: const EdgeInsets.only(top: Gaps.sm, bottom: Gaps.sm),
                      child: ColorPicker(
                        color: selected,
                        showOpacity: false,
                        showSwatches: false,
                        onChanged: _pick,
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        );
      },
    );
  }
}
