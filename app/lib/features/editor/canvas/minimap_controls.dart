import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_theme.dart';
import '../chrome/bar_button.dart';

/// The row of buttons under the minimap: zoom the canvas out and in, fit
/// all of its content, fold the map. As wide as the map, each button an
/// equal share of it, as tall as a slot's hit area (44 on touch).
class MinimapControls extends StatelessWidget {
  const MinimapControls({
    super.key,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onFit,
    required this.onFold,
  });

  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onFit;
  final VoidCallback onFold;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget button(IconData icon, String tip, VoidCallback onPressed) => Expanded(
      child: IconButton(
        icon: Icon(icon, size: Glyphs.menu),
        tooltip: tip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.expand(),
        style: IconButton.styleFrom(
          shape: const RoundedRectangleBorder(),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(border: Border(top: Surfaces.border(scheme) ?? BorderSide.none)),
      child: SizedBox(
        height: Targets.slotHit(context),
        child: Row(
          children: [
            button(Symbols.remove_rounded, 'Zoom out', onZoomOut),
            button(Symbols.add_rounded, 'Zoom in', onZoomIn),
            button(Symbols.zoom_out_map_rounded, 'Fit content', onFit),
            button(Symbols.collapse_content_rounded, 'Fold minimap', onFold),
          ],
        ),
      ),
    );
  }
}

/// The minimap folded away: a bar button in its corner that unfolds it.
class MinimapFoldedButton extends StatelessWidget {
  const MinimapFoldedButton({super.key, required this.onUnfold});

  final VoidCallback onUnfold;

  /// Its tooltip.
  static const String tooltip = 'Show minimap';

  @override
  Widget build(BuildContext context) =>
      BarButton(icon: Symbols.map_rounded, tooltip: tooltip, onPressed: onUnfold);
}
