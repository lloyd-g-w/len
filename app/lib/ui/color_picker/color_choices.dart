import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../app_theme.dart';
import '../color_dot.dart';
import '../even_grid.dart';
import '../section_label.dart';
import 'color_picker.dart';
import 'color_swatches.dart';

/// The colour block every tool popover shares: a "Colour" heading with
/// Custom (opens the full picker in place), a [palette] (seven per row:
/// 2 × 7 pen colours, 2 × 5 highlighter ones), then the [recent] colours,
/// lined up with the palette's columns. Every pick applies at once through [onChanged] (opaque ARGB).
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

  /// Colours picked recently, most recent first; one row of them shows.
  final List<int> recent;

  @override
  State<ColorChoices> createState() => _ColorChoicesState();
}

class _ColorChoicesState extends State<ColorChoices> {
  /// Whether the custom picker is open.
  bool _customOpen = false;

  static const int _columns = 7;
  static const double _gap = 4;

  void _pick(int argb) => widget.onChanged(argb | 0xFF000000);

  @override
  Widget build(BuildContext context) {
    final selected = widget.color | 0xFF000000;
    final recent = [
      for (final c in widget.recent)
        if (!widget.palette.contains(c | 0xFF000000)) c | 0xFF000000,
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = ((constraints.maxWidth - _gap * (_columns - 1)) / _columns).clamp(20.0, 32.0);
        // On touch the swatches get 48-dp cells (EvenGrid) spread across the
        // full width; a pointer keeps the 4-dp grid.
        final touch = Targets.touchFirst;
        final visual = touch ? 32.0 : size;
        // The palette's columns, as EvenGrid lays them out (touch cells are
        // 48 dp with no spacing of their own). Recent colours keep its
        // spacing and fill at most one row, so they line up with it.
        final columns = EvenGridSpec(
          itemExtent: touch ? Targets.touch : size,
          minItemExtent: touch ? Targets.touch : size,
          minSpacing: touch ? 0 : _gap,
          runSpacing: 0,
          maxSpacing: touch ? double.infinity : _gap,
        ).resolve(widget.palette.length, constraints.maxWidth);
        Widget grid(List<int> colours, {required double maxSpacing}) => EvenGrid(
          itemExtent: size,
          minSpacing: _gap,
          runSpacing: _gap,
          maxSpacing: maxSpacing,
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
                    _customOpen ? Symbols.expand_less_sharp : Symbols.palette_sharp,
                    size: Glyphs.menu,
                  ),
                  label: const Text('Custom'),
                ),
              ],
            ),
            grid(widget.palette, maxSpacing: touch ? double.infinity : _gap),
            if (recent.isNotEmpty) ...[
              const SizedBox(height: Gaps.sm),
              const SectionLabel('Recent'),
              const SizedBox(height: Gaps.xs),
              grid(recent.take(columns.columns).toList(), maxSpacing: columns.spacing),
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
