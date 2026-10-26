import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../platform/coarse_pointer.dart';

/// Durations and curves for every animation in the app: use these rather
/// than literals so the app moves with one rhythm.
abstract final class Motion {
  /// Small state changes: selection plates, icons swapping, hovers, and
  /// popovers and menus dropping in from their anchor.
  static const Duration fast = Duration(milliseconds: 100);

  /// Chrome fading in and out, panels, chips and size changes.
  static const Duration medium = Duration(milliseconds: 180);

  /// Larger surfaces entering: sheets, dialogs, route transitions.
  static const Duration slow = Duration(milliseconds: 260);

  /// Travelling a distance on screen (scrolling to a page or a match).
  static const Duration travel = Duration(milliseconds: 400);

  /// How far chrome slides toward its edge while it fades out (never a
  /// whole bar's height).
  static const double chromeSlide = 8;

  /// How far popovers and menus drop from their anchor while they fade in.
  static const double popoverDrop = 4;

  /// The scale menus grow from at their anchor (1: they only fade and
  /// drop; DESIGN §5 has no scaling bloom).
  static const double popoverScale = 1;

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

  /// [duration] for something that moves (slides, travels, grows, turns),
  /// or zero when the platform asks for reduced motion (DESIGN §5: fades
  /// only). Fades and colour changes keep their durations.
  static Duration moving(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;
}

/// Responsive breakpoints (logical pixels of window width).
abstract final class Breakpoints {
  /// Below this: phone layout (the library's drawer, sheets instead of
  /// dialogs, a single column).
  static const double medium = 840;

  /// From here: full sidebar with labels.
  static const double expanded = 1040;

  /// Below this window height the library keeps its phone layout even
  /// when wide: a phone held sideways is still a phone, and a sidebar
  /// would leave its folders a sliver.
  static const double shortHeight = 480;

  /// Whether a window of [size] gets the library's phone layout.
  static bool libraryCompact(Size size) => size.width < medium || size.height < shortHeight;

  /// Whether a window of [size] is short (a phone held sideways): chrome
  /// packs into one row so the content keeps the height.
  static bool short(Size size) => size.height < shortHeight;
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

/// Glyph sizes for Material Symbols Rounded, by where they sit.
abstract final class Glyphs {
  /// Bars and the toolbar.
  static const double bar = 20;

  /// Menu rows and list rows.
  static const double menu = 18;

  /// Small marks beside text or on a thumbnail: a bookmark ribbon in a
  /// strip, a menu caret, a cover's badge.
  static const double badge = 16;

  /// A quick slot's colour dot.
  static const double slotDot = 22;

  /// Empty states.
  static const double empty = 40;

  /// The stroke weight of every symbol (fill 0; active states fill 1).
  static const double weight = 300;
}

/// Hairlines (DESIGN §3): chrome is separated by 1-dp rules, as a ruled
/// page separates its lines; the accent's margin rule is 2 dp.
abstract final class Hairline {
  /// A hairline: dividers, the edge of docked chrome, surface borders.
  static const double width = 1;

  /// The margin rule that marks where you are, and a focused field's rule.
  static const double rule = 2;
}

/// Depth, the only source of elevation (no Material `elevation`; DESIGN
/// §3): only paper has depth. Level 1 ([low], "contact") for paper at
/// rest (pages, covers, thumbnails) and the floating palette; level 2
/// ([high], "lifted") for slips over the page: popovers, menus, dialogs and
/// dragged items. Chrome is flat. Raised and overlay surfaces also carry a
/// hairline (see `Surfaces`).
abstract final class Shadows {
  /// Level 1: paper resting on the desk.
  static List<BoxShadow> low(Brightness b) => [
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: b == Brightness.dark ? 0.40 : 0.10),
      blurRadius: 1,
      offset: const Offset(0, 1),
    ),
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: b == Brightness.dark ? 0.30 : 0.06),
      blurRadius: 6,
      offset: const Offset(0, 2),
    ),
  ];

  /// Level 2: a slip held above the page.
  static List<BoxShadow> high(Brightness b) => [
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: b == Brightness.dark ? 0.40 : 0.08),
      blurRadius: 2,
      offset: const Offset(0, 1),
    ),
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: b == Brightness.dark ? 0.50 : 0.12),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];
}
