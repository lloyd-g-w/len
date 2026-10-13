import 'package:flutter/material.dart';

/// Lets [child]'s Material chips show the surface they sit on. A chip
/// paints its outline and selected plate on its own `Material`, whose
/// colour falls back to the theme's canvas (the screen's surface): on a
/// dialog or sheet, unselected chips then read as dark holes in dark mode.
class ChipSurface extends StatelessWidget {
  const ChipSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(canvasColor: Colors.transparent),
    child: child,
  );
}
