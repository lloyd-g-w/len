import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../app_theme.dart';
import '../color_dot.dart';

/// The last swatch of a colour row: opens a colour picker; shows the
/// custom [color] (selected) once there is one.
class CustomColorSwatch extends StatelessWidget {
  const CustomColorSwatch({super.key, required this.color, required this.onTap});

  final int? color;
  final void Function(BuildContext context) onTap;

  @override
  Widget build(BuildContext context) {
    final colour = color;
    if (colour != null) {
      return ColorDot(
        color: colour,
        size: 28,
        selected: true,
        tooltip: 'Custom colour…',
        onTap: () => onTap(context),
      );
    }
    return SizedBox.square(
      dimension: 28,
      child: IconButton(
        tooltip: 'Custom colour…',
        padding: EdgeInsets.zero,
        iconSize: Glyphs.menu,
        onPressed: () => onTap(context),
        icon: const Icon(Symbols.palette_sharp),
      ),
    );
  }
}
