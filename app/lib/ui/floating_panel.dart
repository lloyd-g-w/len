import 'package:flutter/material.dart';

import 'app_theme.dart';

/// A `raised` surface (level 1) floating over the canvas: the floating
/// palette, pills, the selection menu and the text format bar. White (dark:
/// `#26262B` with a hairline), [Shadows.low], corner [radius] ([Radii.md];
/// [Radii.pill] for pills).
class FloatingPanel extends StatelessWidget {
  const FloatingPanel({super.key, required this.child, this.padding, this.radius = Radii.md});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  /// The corner radius.
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: Shadows.low(scheme.brightness),
      ),
      child: Material(
        color: Surfaces.raised(scheme.brightness),
        shape: Surfaces.shape(scheme, radius),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding:
              padding ?? const EdgeInsets.symmetric(horizontal: Gaps.xs + 2, vertical: Gaps.xs),
          child: child,
        ),
      ),
    );
  }
}
