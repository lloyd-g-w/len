import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../platform/coarse_pointer.dart';

/// Durations and curves for every animation in the app: use these rather
/// than literals so the app moves with one rhythm.
abstract final class Motion {
  /// Small state changes: selection plates, icons swapping, hovers, and
  /// popovers and menus scaling in from their anchor.
  static const Duration fast = Duration(milliseconds: 120);

  /// Chrome fading in and out, panels, chips and size changes.
  static const Duration medium = Duration(milliseconds: 200);

  /// Larger surfaces entering: sheets, dialogs, route transitions.
  static const Duration slow = Duration(milliseconds: 300);

  /// Travelling a distance on screen (scrolling to a page or a match).
  static const Duration travel = Duration(milliseconds: 420);

  /// How far chrome slides toward its edge while it fades out (never a
  /// whole bar's height).
  static const double chromeSlide = 8;

  /// The scale popovers and menus grow from, at their anchor.
  static const double popoverScale = 0.96;

  /// Entering and settling (decelerate).
  static const Curve standard = Curves.easeOutCubic;

  /// Prominent entrances (decelerate harder).
  static const Curve emphasized = Curves.easeOutQuart;

  /// Leaving the screen (accelerate).
  static const Curve exit = Curves.easeIn;

  /// Moving between two places that are both on screen.
  static const Curve move = Curves.easeInOutCubic;

  /// Whether the platform asks for reduced motion: animate with fades only.
  static bool reduced(BuildContext context) => MediaQuery.disableAnimationsOf(context);
}

/// Responsive breakpoints (logical pixels of window width).
abstract final class Breakpoints {
  /// Below this: phone layout (the library's drawer, sheets instead of
  /// dialogs, a single column).
  static const double medium = 840;

  /// From here: full sidebar with labels.
  static const double expanded = 1040;
}

/// Touch target sizes, decided by input rather than width: touch-first
/// devices (Android, or a coarse pointer on the web) get [touch]-sized hit
/// areas; with a mouse or trackpad controls keep their compact size.
abstract final class Targets {
  /// The smallest comfortable touch target (Material's minimum).
  static const double touch = 48;

  /// A control's visual size in bars and toolbars (glyph [Glyphs.bar]).
  static const double bar = 40;

  /// A quick slot's cell (a 22-dp dot inside).
  static const double slot = 36;

  /// A quick slot's hit area on touch.
  static const double slotTouch = 44;

  /// Menu rows with a pointer: 44 high ([touch] on touch).
  static const double menuRow = 44;

  /// Overrides [touchFirst] in tests.
  @visibleForTesting
  static bool? debugTouchFirst;

  /// Whether the device is used mainly with fingers: Android, or a coarse
  /// primary pointer on the web.
  static bool get touchFirst =>
      debugTouchFirst ??
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          (kIsWeb && primaryPointerIsCoarse));

  /// The hit area for a control drawn [visual] wide: at least [touch] on
  /// touch-first devices, [visual] with a pointer.
  static double of(BuildContext context, double visual) =>
      touchFirst && visual < touch ? touch : visual;

  /// The hit area of a bar or toolbar button: 48 on touch, 40 with a
  /// pointer.
  static double barHit(BuildContext context) => of(context, bar);

  /// The hit area of a quick slot: 44 on touch, 36 with a pointer.
  static double slotHit(BuildContext context) => touchFirst ? slotTouch : slot;

  /// The height of a menu row: 48 on touch, 44 with a pointer.
  static double menuRowHeight(BuildContext context) => touchFirst ? touch : menuRow;
}

/// Glyph sizes for Material Symbols, by where they sit.
abstract final class Glyphs {
  /// Bars and the toolbar.
  static const double bar = 20;

  /// Menu rows and list rows.
  static const double menu = 18;

  /// A quick slot's colour dot.
  static const double slotDot = 22;

  /// Empty states.
  static const double empty = 40;

  /// The stroke weight of every symbol (fill 0; active states fill 1).
  static const double weight = 300;
}

/// Shadow levels, the only source of elevation (no Material `elevation`):
/// level 1 ([low]) for `raised` surfaces, level 2 ([high]) for overlays.
/// Dark mode adds a hairline border instead (see `Surfaces`).
abstract final class Shadows {
  /// Level 1: the floating palette, pills, the selection menu, covers.
  static List<BoxShadow> low(Brightness b) => [
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: b == Brightness.dark ? 0.30 : 0.05),
      blurRadius: 2,
      offset: const Offset(0, 1),
    ),
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: b == Brightness.dark ? 0.24 : 0.06),
      blurRadius: 10,
      offset: const Offset(0, 3),
    ),
  ];

  /// Level 2: popovers, menus, dialogs and sheets.
  static List<BoxShadow> high(Brightness b) => [
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: b == Brightness.dark ? 0.36 : 0.06),
      blurRadius: 4,
      offset: const Offset(0, 2),
    ),
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: b == Brightness.dark ? 0.44 : 0.12),
      blurRadius: 28,
      offset: const Offset(0, 12),
    ),
  ];
}
