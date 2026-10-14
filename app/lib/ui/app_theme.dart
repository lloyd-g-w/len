import 'package:flutter/material.dart';

import 'design_tokens.dart';
import 'surfaces.dart';
import 'theme_components.dart';
import 'tones.dart';

export 'design_tokens.dart';
export 'surfaces.dart';
export 'tones.dart';

/// Visual language (DESIGN.md): Swiss minimal from the notebook. True
/// neutral greys, black ink, one accent (ruling blue) for state, Sofia Sans
/// in a six-role scale, Material Symbols Sharp, flat chrome with hairlines,
/// and depth only for paper ([Shadows]).
abstract final class AppTheme {
  /// The weight of the current or chosen row's label in a list (the
  /// sidebar, Move, the pickers, the outline, the overview, the tab
  /// switcher): with the margin rule, "a bold label" (DESIGN §6). Selected
  /// chips and segments, on an Ink plate, stay semibold.
  static const FontWeight currentWeight = FontWeight.w700;

  /// The accent: ruling blue (light theme).
  static const Color seed = Color(0xFF0068C9);

  /// The light theme.
  static ThemeData light() => _build(Brightness.light);

  /// The dark theme.
  static ThemeData dark() => _build(Brightness.dark);

  /// The colour scheme for [brightness]: every role Len uses set from
  /// [Tones], so no generated tonal colour shows up.
  static ColorScheme scheme(Brightness brightness) {
    final t = Tones.of(brightness);
    final light = brightness == Brightness.light;
    final base = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    // Containers between Board and Sheet, for the few plates left.
    final containers = light
        ? const [0xFFFFFFFF, 0xFFEEEEEE, 0xFFE9E9E9, 0xFFE3E3E3, 0xFFDDDDDD]
        : const [0xFF141414, 0xFF1F1F1F, 0xFF232323, 0xFF2B2B2B, 0xFF333333];
    final plate = Color(containers[3]);
    return base.copyWith(
      primary: t.accent,
      onPrimary: t.onAccent,
      // Tonal roles stay neutral: the accent is kept for state.
      primaryContainer: plate,
      onPrimaryContainer: t.ink,
      secondary: t.ink,
      onSecondary: t.board,
      secondaryContainer: plate,
      onSecondaryContainer: t.ink,
      tertiary: t.graphite,
      onTertiary: t.board,
      tertiaryContainer: plate,
      onTertiaryContainer: t.ink,
      error: t.error,
      onError: light ? const Color(0xFFFFFFFF) : const Color(0xFF000000),
      surface: t.board,
      onSurface: t.ink,
      onSurfaceVariant: t.graphite,
      surfaceDim: t.desk,
      surfaceBright: t.sheet,
      surfaceContainerLowest: Color(containers[0]),
      surfaceContainerLow: Color(containers[1]),
      surfaceContainer: Color(containers[2]),
      surfaceContainerHigh: Color(containers[3]),
      surfaceContainerHighest: Color(containers[4]),
      outline: t.pencil,
      outlineVariant: t.rule,
      inverseSurface: t.ink,
      onInverseSurface: t.board,
      inversePrimary: Tones.of(light ? Brightness.dark : Brightness.light).accent,
      shadow: const Color(0xFF000000),
      scrim: const Color(0xFF000000),
      surfaceTint: Colors.transparent,
    );
  }

  /// The UI font on every platform (bundled; see `pubspec.yaml`). Text
  /// boxes and planner labels keep their own faces (`TextFont`).
  static const String fontFamily = 'Sofia Sans';

  static ThemeData _build(Brightness brightness) {
    final scheme = AppTheme.scheme(brightness);
    final base = ThemeData(colorScheme: scheme, useMaterial3: true, fontFamily: fontFamily);
    final pressed = Surfaces.pressed(scheme);
    return base
        .copyWith(
          scaffoldBackgroundColor: scheme.surface,
          canvasColor: scheme.surface,
          textTheme: _textTheme(base.textTheme, scheme),
          // Taps: no ripple or sparkle, a calm ink highlight instead.
          splashFactory: NoSplash.splashFactory,
          splashColor: Colors.transparent,
          highlightColor: pressed,
          hoverColor: Surfaces.hovered(scheme),
          focusColor: pressed,
          iconTheme: IconThemeData(
            color: scheme.onSurface,
            size: Glyphs.bar,
            weight: Glyphs.weight,
            fill: 0,
            grade: 0,
            opticalSize: 20,
          ),
          visualDensity: VisualDensity.standard,
          textSelectionTheme: TextSelectionThemeData(
            cursorColor: scheme.primary,
            selectionColor: scheme.primary.withValues(alpha: 0.24),
            selectionHandleColor: scheme.primary,
          ),
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: {
              TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
              TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
              TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
              TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
            },
          ),
        )
        .applyComponentThemes(scheme);
  }

  /// The type scale (DESIGN §2): six roles, all Sofia Sans, one size up
  /// from the usual UI scale for its small x-height. Title (`titleLarge`),
  /// Heading (`titleMedium`), Body (`bodyMedium`), Label (`labelLarge`),
  /// Caption (`bodySmall`) and Small label (`labelSmall`). Material's other
  /// slots alias onto them, so built-in widgets match.
  static TextTheme _textTheme(TextTheme t, ColorScheme scheme) {
    TextStyle style(double size, double line, FontWeight weight, [double tracking = 0]) =>
        TextStyle(
          fontFamily: fontFamily,
          fontSize: size,
          height: line / size,
          fontWeight: weight,
          letterSpacing: tracking,
          color: scheme.onSurface,
          leadingDistribution: TextLeadingDistribution.even,
        );
    final title = style(24, 28, FontWeight.w600, -0.4);
    final heading = style(18, 24, FontWeight.w600, -0.2);
    final body = style(15, 20, FontWeight.w400);
    final label = style(15, 20, FontWeight.w500);
    final caption = style(13, 16, FontWeight.w400, 0.1).copyWith(color: scheme.onSurfaceVariant);
    final small = style(12, 16, FontWeight.w600, 0.2);
    return t.merge(
      TextTheme(
        displayLarge: title,
        displayMedium: title,
        displaySmall: title,
        headlineLarge: title,
        headlineMedium: title,
        headlineSmall: title,
        titleLarge: title,
        titleMedium: heading,
        titleSmall: label,
        bodyLarge: body,
        bodyMedium: body,
        bodySmall: caption,
        labelLarge: label,
        labelMedium: caption.copyWith(fontWeight: FontWeight.w500),
        labelSmall: small,
      ),
    );
  }

  /// Tabular figures, for page numbers, times and zoom percentages.
  static const List<FontFeature> tabularFigures = [FontFeature.tabularFigures()];
}

/// Spacing on a 4-dp grid (2 only inside controls).
abstract final class Gaps {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

/// Corner radii (DESIGN §3): tight, by object size. A page's corner is
/// square; nothing uses one radius for everything.
abstract final class Radii {
  /// Chips, badges, plates, tooltips, the plate behind the selected tool.
  static const double xs = 2;

  /// Buttons, fields, segmented controls, covers, thumbnails, focus ring.
  static const double sm = 4;

  /// Menus, popovers, the floating palette, snack bars.
  static const double md = 6;

  /// Dialogs and the top of bottom sheets.
  static const double lg = 8;

  /// Colour dots and the page indicator.
  static const double pill = 999;
}

/// Preset colours offered in pickers, and shared fixed colours.
abstract final class Palette {
  /// Default paper colour (matches `PaperPainter`), for previews of ink on
  /// paper outside the editor (pen previews, notebook covers).
  static const Color paper = Color(0xFFFFFDF8);

  /// Bookmark ribbons on pages and thumbnails (a marker, like ink: not
  /// themed).
  static const Color bookmark = Color(0xFFE8590C);

  /// Shades what a crop cuts away (image crop, scan corners): over a photo,
  /// not the chrome, so the same in both themes.
  static const Color cropShade = Color(0x99000000);

  static const List<int> covers = [
    0xFF3B5BDB, // ink blue
    0xFF0CA678, // teal
    0xFFF08C00, // amber
    0xFFE8590C, // orange
    0xFFC2255C, // raspberry
    0xFF7048E8, // violet
    0xFF495057, // graphite
    0xFF2B8A3E, // forest
    0xFF0B7285, // lagoon
    0xFFB08968, // sand
  ];

  /// Names of [covers], in the same order (tooltips, accessibility).
  static const List<String> coverNames = [
    'Ink blue',
    'Teal',
    'Amber',
    'Orange',
    'Raspberry',
    'Violet',
    'Graphite',
    'Forest',
    'Lagoon',
    'Sand',
  ];

  /// The name of cover colour [argb], if it is one of [covers].
  static String? coverName(int argb) {
    final i = covers.indexOf(argb);
    return i < 0 ? null : coverNames[i];
  }
}
