import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/stroke.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/color_dot.dart';
import '../../../ui/color_picker/color_names.dart';

/// "Highlight" in the PDF text selection menu: the highlighter's quick
/// colours as swatches (up to [max]), its current one first and ringed. One tap
/// highlights the selection in that colour (the highlighter itself keeps
/// its colour). A quiet highlighter glyph says what the dots do.
class PdfHighlightSwatches extends StatelessWidget {
  const PdfHighlightSwatches({super.key, required this.tools, required this.onHighlight});

  final ToolSettings tools;

  /// Highlights the selection in an opaque ARGB colour.
  final ValueChanged<int> onHighlight;

  /// At most this many swatches, so the menu fits a phone.
  static const int max = 3;

  /// The quick colours, the current one first, at most [max].
  static List<int> colorsOf(PenConfig config) => [
    config.color,
    for (final (i, c) in config.colors.indexed)
      if (i != config.colorIndex && c != config.color) c,
  ].take(max).toList();

  @override
  Widget build(BuildContext context) {
    final colors = colorsOf(tools.configOf(InkTool.highlighter));
    final target = Targets.barHit(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gaps.xs),
          child: Icon(
            Symbols.border_color_sharp,
            size: Glyphs.menu,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        for (final (i, color) in colors.indexed)
          ColorDot(
            key: ValueKey(i == 0 ? 'pdf-highlight' : 'pdf-highlight-$i'),
            color: color,
            selected: i == 0,
            size: Glyphs.slotDot + Gaps.xs,
            target: target,
            tooltip: 'Highlight in ${colorName(color)}',
            onTap: () => onHighlight(color),
          ),
      ],
    );
  }
}
