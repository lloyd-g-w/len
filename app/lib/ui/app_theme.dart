import 'package:flutter/material.dart';

import 'design_tokens.dart';
import 'surfaces.dart';
import 'theme_components.dart';

export 'design_tokens.dart';
export 'surfaces.dart';

/// Visual language (REDESIGN §1): calm, paper-like neutrals with one fixed
/// ink-blue accent, Inter in a six-role type scale, Material Symbols
/// Rounded, flat chrome and shadows only from [Shadows].
abstract final class AppTheme {
  /// The accent: ink blue.
  static const Color seed = Color(0xFF3B5BDB);

  /// The light theme.
  static ThemeData light() => _build(Brightness.light);

  /// The dark theme.
  static ThemeData dark() => _build(Brightness.dark);

  /// The colour scheme for [brightness]: accent roles from [seed], quiet
  /// neutral surfaces so notebook covers carry the colour.
  static ColorScheme scheme(Brightness brightness) {
    final base = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    return brightness == Brightness.light
        ? base.copyWith(
            surface: const Color(0xFFF9F9F7),
            onSurface: const Color(0xFF1B1B1F),
            onSurfaceVariant: const Color(0xFF66666E),
            surfaceContainerLowest: const Color(0xFFFFFFFF),
            surfaceContainerLow: const Color(0xFFF3F3F0),
            surfaceContainer: const Color(0xFFEDEDEA),
            surfaceContainerHigh: const Color(0xFFE7E7E4),
            surfaceContainerHighest: const Color(0xFFE0E0DD),
            outline: const Color(0xFFADADB4),
            outlineVariant: const Color(0xFFE1E1DE),
            // Tonal roles stay neutral: the accent is kept for primary actions.
            secondaryContainer: const Color(0xFFE7E7E4),
            onSecondaryContainer: const Color(0xFF1B1B1F),
            surfaceTint: Colors.transparent,
          )
        : base.copyWith(
            surface: const Color(0xFF131316),
            onSurface: const Color(0xFFECECF0),
            onSurfaceVariant: const Color(0xFF9F9FA9),
            surfaceContainerLowest: const Color(0xFF0E0E10),
            surfaceContainerLow: const Color(0xFF18181C),
            surfaceContainer: const Color(0xFF1E1E22),
            surfaceContainerHigh: const Color(0xFF26262B),
            surfaceContainerHighest: const Color(0xFF2F2F35),
            outline: const Color(0xFF5C5C66),
            outlineVariant: const Color(0xFF2C2C32),
            secondaryContainer: const Color(0xFF2F2F35),
            onSecondaryContainer: const Color(0xFFECECF0),
            surfaceTint: Colors.transparent,
          );
  }

  /// The UI font on every platform (bundled; see `pubspec.yaml`).
  static const String fontFamily = 'Inter';

  static ThemeData _build(Brightness brightness) {
    final scheme = AppTheme.scheme(brightness);
    final base = ThemeData(colorScheme: scheme, useMaterial3: true, fontFamily: fontFamily);
    final pressed = Surfaces.pressed(scheme);
    return base
        .copyWith(
          scaffoldBackgroundColor: scheme.surface,
          textTheme: _textTheme(base.textTheme, scheme),
          // Taps: no ripple or sparkle, a calm onSurface highlight instead.
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

  /// The type scale (REDESIGN §1.2): six roles, all Inter. Title
  /// (`titleLarge`), Heading (`titleMedium`), Body (`bodyMedium`), Label
  /// (`labelLarge`), Caption (`bodySmall`) and Overline (`labelSmall`).
  /// Material's other slots alias onto them, so built-in widgets match.
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
    final title = style(20, 26, FontWeight.w600, -0.2);
    final heading = style(16, 22, FontWeight.w600);
    final body = style(14, 20, FontWeight.w400);
    final label = style(14, 20, FontWeight.w500);
    final caption = style(12, 16, FontWeight.w400).copyWith(color: scheme.onSurfaceVariant);
    final overline = style(11, 14, FontWeight.w600, 0.3);
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
        labelSmall: overline,
      ),
    );
  }

  /// Tabular figures, for page numbers, times and zoom percentages.
  static const List<FontFeature> tabularFigures = [FontFeature.tabularFigures()];
}

/// Spacing scale used for padding and gaps.
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

/// Corner radii used across the app.
abstract final class Radii {
  /// Chips, badges, the plate behind the selected tool.
  static const double xs = 6;

  /// Buttons, fields, quick slots, covers, page thumbnails.
  static const double sm = 10;

  /// Menus, popovers, the floating palette, snack bars.
  static const double md = 14;

  /// Dialogs and bottom sheets.
  static const double lg = 20;

  /// The page indicator, zoom pill and focus puck.
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

  /// The star of favourite notebooks.
  static const Color favourite = Color(0xFFF5A524);

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
