import 'package:flutter/material.dart';

import 'app_theme.dart';

/// A rounded, softly elevated container that floats over the canvas.
class FloatingPanel extends StatelessWidget {
  const FloatingPanel({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      elevation: 3,
      shadowColor: Colors.black26,
      surfaceTintColor: Colors.transparent,
      borderRadius: BorderRadius.circular(Radii.toolbar),
      child: Padding(
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: child,
      ),
    );
  }
}
