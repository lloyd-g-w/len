import 'package:flutter/material.dart';

/// Visual language: calm, paper-like neutrals with an ink-blue accent,
/// generous rounding and soft elevation.
abstract final class AppTheme {
  static const Color seed = Color(0xFF3B5BDB);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
    );
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      textTheme: base.textTheme.copyWith(
        headlineLarge: base.textTheme.headlineLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.card)),
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.control),
          borderSide: BorderSide.none,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.control)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(showDragHandle: true),
      tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 600)),
    );
  }
}

/// Corner radii used across the app.
/// Spacing scale used for padding and gaps.
abstract final class Gaps {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

abstract final class Radii {
  static const double control = 14;
  static const double card = 20;
  static const double toolbar = 28;
}

/// Preset colours offered in pickers.
abstract final class Palette {
  static const List<int> covers = [
    0xFF3B5BDB, // ink blue
    0xFF0CA678, // teal
    0xFFF08C00, // amber
    0xFFE8590C, // orange
    0xFFC2255C, // raspberry
    0xFF7048E8, // violet
    0xFF495057, // graphite
    0xFF2B8A3E, // forest
  ];

  static const List<int> pen = [
    0xFF1F2937, // near-black
    0xFF1C7ED6, // blue
    0xFFE03131, // red
    0xFF2F9E44, // green
    0xFF7048E8, // violet
    0xFFF76707, // orange
  ];

  static const List<int> highlighter = [
    0xFFFACC15, // yellow
    0xFF69DB7C, // green
    0xFF74C0FC, // blue
    0xFFF783AC, // pink
    0xFFFFA94D, // orange
  ];
}
