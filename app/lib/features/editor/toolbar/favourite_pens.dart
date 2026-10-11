import 'package:flutter/material.dart';

import '../../../ink/tool_settings.dart';
import '../../../ui/color_picker/color_hex.dart';
import '../pen/ink_slots.dart';
import '../pen/slot_button.dart';
import 'toolbar_config.dart';

/// A favourite pen's glyph: a disc (pen) or a marker bar (highlighter) in
/// its colour, sized by its width.
class FavouriteGlyph extends StatelessWidget {
  const FavouriteGlyph({super.key, required this.pen});

  final FavouritePen pen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = WidthSlots.dotSize(pen.ink, pen.width).clamp(12.0, 22.0);
    final highlighter = pen.tool == EditorTool.highlighter;
    return Container(
      width: highlighter ? 22 : size,
      height: highlighter ? (size * 0.6).clamp(8.0, 14.0) : size,
      decoration: BoxDecoration(
        color: Color(pen.color).withValues(alpha: highlighter ? 0.75 : 1),
        shape: highlighter ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: highlighter ? BorderRadius.circular(3) : null,
        // Reads on the toolbar for any colour, dark inks in dark mode too.
        border: Border.all(color: scheme.outline, width: 1),
      ),
    );
  }
}

/// A short description of a favourite, e.g. "Pen, #1C4ED8, 2.5".
String describeFavourite(FavouritePen pen) {
  final w = pen.width.toStringAsFixed(pen.width < 10 ? 1 : 0);
  final tool = pen.tool == EditorTool.highlighter ? 'Highlighter' : 'Pen';
  return '$tool, ${ColorHex.rgb(pen.color)}, $w';
}

/// The favourites row of the toolbar: one tap draws with a favourite pen.
class FavouritePens extends StatelessWidget {
  const FavouritePens({super.key, required this.tools, required this.favourites, this.onPicked});

  final ToolSettings tools;
  final List<FavouritePen> favourites;

  /// Called after a favourite was picked.
  final VoidCallback? onPicked;

  /// Width of the row for [count] favourites.
  static double widthFor(int count) => count * SlotButton.size;

  void _pick(FavouritePen pen) {
    pen.applyTo(tools);
    onPicked?.call();
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (i, pen) in favourites.indexed)
        SlotButton(
          key: ValueKey('favourite-$i'),
          selected: pen.isActiveIn(tools),
          tooltip: 'Favourite: ${describeFavourite(pen)}',
          semanticLabel: 'Favourite ${i + 1}: ${describeFavourite(pen)}',
          onSelect: () => _pick(pen),
          onEdit: (_) => _pick(pen),
          child: FavouriteGlyph(pen: pen),
        ),
    ],
  );
}
