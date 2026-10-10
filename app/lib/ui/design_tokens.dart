import 'package:flutter/widgets.dart';

/// Durations and curves for implicit animations.
abstract final class Motion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration medium = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 360);
  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeOutQuart;
}

/// Responsive breakpoints (logical pixels of window width).
abstract final class Breakpoints {
  /// Below this: phone layout (bottom navigation, single column).
  static const double medium = 720;

  /// From here: full sidebar with labels.
  static const double expanded = 1040;
}

/// Soft, layered shadows (key + ambient light).
abstract final class Shadows {
  /// Resting cards and covers.
  static List<BoxShadow> low(Brightness b) => [
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: b == Brightness.dark ? 0.35 : 0.06),
      blurRadius: 2,
      offset: const Offset(0, 1),
    ),
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: b == Brightness.dark ? 0.30 : 0.07),
      blurRadius: 10,
      offset: const Offset(0, 4),
    ),
  ];

  /// Hovered / lifted cards.
  static List<BoxShadow> high(Brightness b) => [
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: b == Brightness.dark ? 0.40 : 0.08),
      blurRadius: 4,
      offset: const Offset(0, 2),
    ),
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: b == Brightness.dark ? 0.45 : 0.14),
      blurRadius: 24,
      offset: const Offset(0, 12),
    ),
  ];
}

/// Accent (seed) colours offered in Settings → Appearance.
abstract final class Accents {
  static const List<int> all = [
    0xFF3B5BDB, // ink blue
    0xFF0B7285, // lagoon
    0xFF2B8A3E, // forest
    0xFFE8590C, // orange
    0xFFC2255C, // raspberry
    0xFF7048E8, // violet
    0xFF495057, // graphite
  ];
}
