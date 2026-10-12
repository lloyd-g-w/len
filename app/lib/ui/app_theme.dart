import 'package:flutter/material.dart';

import 'theme_components.dart';

export 'design_tokens.dart';

/// Visual language: calm, paper-like neutrals with a single accent colour,
/// generous rounding, soft elevation and a tight, modern type scale.
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
            surfaceTint: Colors.transparent,
          );
  }

  static ThemeData _build(Brightness brightness) {
    final scheme = AppTheme.scheme(brightness);
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    return base
        .copyWith(
          scaffoldBackgroundColor: scheme.surface,
          textTheme: _textTheme(base.textTheme, scheme),
          splashFactory: InkSparkle.splashFactory,
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

  /// A tighter, more editorial type scale: heavier headlines with negative
  /// tracking, semibold titles and labels.
  static TextTheme _textTheme(TextTheme t, ColorScheme scheme) {
    TextStyle? tight(TextStyle? s, FontWeight w, double tracking) =>
        s?.copyWith(fontWeight: w, letterSpacing: tracking);
    return t.copyWith(
      displaySmall: tight(t.displaySmall, FontWeight.w700, -1),
      headlineLarge: tight(t.headlineLarge, FontWeight.w700, -0.8),
      headlineMedium: tight(t.headlineMedium, FontWeight.w700, -0.6),
      headlineSmall: tight(t.headlineSmall, FontWeight.w600, -0.4),
      titleLarge: tight(t.titleLarge, FontWeight.w600, -0.2),
      titleMedium: tight(t.titleMedium, FontWeight.w600, -0.1),
      titleSmall: tight(t.titleSmall, FontWeight.w600, 0),
      labelLarge: tight(t.labelLarge, FontWeight.w600, 0.1),
      labelMedium: tight(t.labelMedium, FontWeight.w500, 0.2),
      bodySmall: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
    );
  }
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
  static const double xs = 6;
  static const double sm = 10;
  static const double cover = 12;
  static const double control = 14;
  static const double card = 20;
  static const double toolbar = 28;
  static const double sheet = 28;
  static const double pill = 999;
}

/// Preset colours offered in pickers, and shared fixed colours.
abstract final class Palette {
  /// Default paper colour (matches `PaperPainter`), for previews of ink on
  /// paper outside the editor (pen previews, notebook covers).
  static const Color paper = Color(0xFFFFFDF8);

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
