import 'package:flutter/material.dart';

import 'app_theme.dart';

/// The four surface roles (REDESIGN §1.1). Every container picks one:
///
/// - **canvasBackdrop**: around pages in the editor;
/// - **chrome**: docked bars, the colour scheme's `surface`, with an
///   `outlineVariant` hairline on the edge facing content ([chromeEdge]);
/// - **raised** (level 1): the floating palette, pills, the selection menu
///   ([raisedDecoration]);
/// - **overlay** (level 2): popovers, menus, dialogs and sheets
///   ([overlayDecoration]); dialogs sit over [scrim].
///
/// Shadows come from [Shadows] only. Light mode has no outlines; dark mode
/// gives raised and overlay surfaces a 1-px `outlineVariant` border, since
/// shadows barely show on dark backgrounds.
abstract final class Surfaces {
  /// The editor's backdrop around pages.
  static Color canvasBackdrop(Brightness b) =>
      b == Brightness.dark ? const Color(0xFF0E0E10) : const Color(0xFFEDEDEA);

  /// Docked bars.
  static Color chrome(ColorScheme scheme) => scheme.surface;

  /// The hairline between docked chrome and the content it faces.
  static BorderSide chromeEdge(ColorScheme scheme) => BorderSide(color: scheme.outlineVariant);

  /// Floating palettes, pills and the selection menu.
  static Color raised(Brightness b) =>
      b == Brightness.dark ? const Color(0xFF26262B) : const Color(0xFFFFFFFF);

  /// Popovers, menus, dialogs and sheets.
  static Color overlay(Brightness b) => raised(b);

  /// The scrim behind dialogs: black at 32 % (light) or 56 % (dark).
  static Color scrim(Brightness b) =>
      const Color(0xFF000000).withValues(alpha: b == Brightness.dark ? 0.56 : 0.32);

  /// The calm press and selection overlay: `onSurface` at 8 % (12 % dark).
  static Color pressed(ColorScheme scheme) =>
      scheme.onSurface.withValues(alpha: scheme.brightness == Brightness.dark ? 0.12 : 0.08);

  /// The hover overlay: `onSurface` at 4 % (6 % dark).
  static Color hovered(ColorScheme scheme) =>
      scheme.onSurface.withValues(alpha: scheme.brightness == Brightness.dark ? 0.06 : 0.04);

  /// The border of raised and overlay surfaces: none in light mode, a
  /// hairline in dark mode.
  static BorderSide? border(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark ? BorderSide(color: scheme.outlineVariant) : null;

  /// The shape of a raised or overlay surface with [radius].
  static RoundedRectangleBorder shape(ColorScheme scheme, double radius) => RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(radius),
    side: border(scheme) ?? BorderSide.none,
  );

  /// A `raised` box (level 1) with corner [radius].
  static BoxDecoration raisedDecoration(ColorScheme scheme, {double radius = Radii.md}) =>
      _decoration(scheme, radius, Shadows.low(scheme.brightness));

  /// An `overlay` box (level 2) with corner [radius].
  static BoxDecoration overlayDecoration(ColorScheme scheme, {double radius = Radii.md}) =>
      _decoration(scheme, radius, Shadows.high(scheme.brightness));

  static BoxDecoration _decoration(ColorScheme scheme, double radius, List<BoxShadow> shadows) {
    final side = border(scheme);
    return BoxDecoration(
      color: raised(scheme.brightness),
      borderRadius: BorderRadius.circular(radius),
      border: side == null ? null : Border.fromBorderSide(side),
      boxShadow: shadows,
    );
  }
}

/// An `overlay` surface (level 2: [Shadows.high], a hairline in dark mode)
/// that hosts ink effects: hand-built menus and popovers. Prefer the
/// primitives (`showAdaptivePopover`, `MenuRow`, `AppDialog`) where they fit.
class OverlaySurface extends StatelessWidget {
  const OverlaySurface({super.key, required this.child, this.radius = Radii.md});

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: Shadows.high(scheme.brightness),
      ),
      child: Material(
        color: Surfaces.overlay(scheme.brightness),
        shape: Surfaces.shape(scheme, radius),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}
