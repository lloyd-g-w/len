import 'package:flutter/material.dart';

import 'app_theme.dart';

/// The four surface roles (DESIGN §1, §3). Every container picks one:
///
/// - **canvasBackdrop**: the Desk around pages in the editor, a step darker
///   than the page so the page is the brightest thing;
/// - **chrome**: docked bars and screens, the scheme's `surface` (Board),
///   flat, with a hairline on the edge facing content ([chromeEdge]);
/// - **raised** (level 1): the floating palette, pills, the selection menu
///   ([raisedDecoration]);
/// - **overlay** (level 2): popovers, menus, dialogs and sheets
///   ([overlayDecoration]); dialogs sit over [scrim].
///
/// Raised and overlay surfaces are Sheet with a hairline ([border]) in both
/// themes, plus their shadow from [Shadows]: only paper has depth.
abstract final class Surfaces {
  /// The editor's Desk around pages.
  static Color canvasBackdrop(Brightness b) => Tones.of(b).desk;

  /// Docked bars.
  static Color chrome(ColorScheme scheme) => scheme.surface;

  /// The hairline between docked chrome and the content it faces.
  static BorderSide chromeEdge(ColorScheme scheme) =>
      BorderSide(color: scheme.outlineVariant, width: Hairline.width);

  /// Floating palettes, pills and the selection menu.
  static Color raised(Brightness b) => Tones.of(b).sheet;

  /// Popovers, menus, dialogs and sheets.
  static Color overlay(Brightness b) => raised(b);

  /// The scrim behind dialogs: black at 32 % (light) or 60 % (dark).
  static Color scrim(Brightness b) =>
      const Color(0xFF000000).withValues(alpha: b == Brightness.dark ? 0.60 : 0.32);

  /// The calm press and selection plate: ink at 8 % (12 % dark).
  static Color pressed(ColorScheme scheme) =>
      scheme.onSurface.withValues(alpha: scheme.brightness == Brightness.dark ? 0.12 : 0.08);

  /// A firm selection plate (a chosen segment or chip): ink at 12 % (20 %
  /// dark), so the choice reads at a glance.
  static Color selected(ColorScheme scheme) =>
      scheme.onSurface.withValues(alpha: scheme.brightness == Brightness.dark ? 0.20 : 0.12);

  /// The hover overlay: ink at 4 % (6 % dark).
  static Color hovered(ColorScheme scheme) =>
      scheme.onSurface.withValues(alpha: scheme.brightness == Brightness.dark ? 0.06 : 0.04);

  /// The hairline edge of raised and overlay surfaces, in both themes
  /// (dark mode lifts it a step so it reads against the Sheet).
  static BorderSide? border(ColorScheme scheme) => BorderSide(
    color: scheme.brightness == Brightness.dark ? const Color(0xFF3D3D3D) : scheme.outlineVariant,
    width: Hairline.width,
  );

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

/// An `overlay` surface (level 2: [Shadows.high] and a hairline) that hosts
/// ink effects: hand-built menus and popovers. Prefer the primitives
/// (`showAdaptivePopover`, `MenuRow`, `AppDialog`) where they fit.
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
