import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/stroke.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/color_dot.dart';
import '../../../ui/color_picker/color_names.dart';

/// "Highlight" in the PDF text selection menu: the highlighter's quick
/// colours as swatches (up to [max]), its current one first (the order says
/// it: no ring, as these are actions, not a choice). One tap highlights the
/// selection in that colour (the highlighter itself keeps its colour). The
/// word "Highlight" ([labelled], where there is room) or a quiet
/// highlighter glyph says what the dots do.
class PdfHighlightSwatches extends StatelessWidget {
  const PdfHighlightSwatches({
    super.key,
    required this.tools,
    required this.onHighlight,
    this.labelled = false,
  });

  final ToolSettings tools;

  /// Says "Highlight" before the dots, rather than showing a glyph.
  final bool labelled;

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
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Each dot says what it does to a screen reader.
        ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: Gaps.sm, end: Gaps.xs),
            child: labelled
                ? Text('Highlight', style: theme.textTheme.labelLarge?.copyWith(color: muted))
                : Icon(Symbols.border_color_sharp, size: Glyphs.menu, color: muted),
          ),
        ),
        for (final (i, color) in colors.indexed)
          ColorDot(
            key: ValueKey(i == 0 ? 'pdf-highlight' : 'pdf-highlight-$i'),
            color: color,
            selected: false,
            size: Glyphs.slotDot + Gaps.xs,
            target: target,
            tooltip: 'Highlight in ${colorName(color)}',
            onTap: () => onHighlight(color),
          ),
      ],
    );
  }
}
