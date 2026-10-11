import 'dart:ui';

import '../../ink/navigation/viewport_animator.dart';
import '../../ink/viewport.dart';

/// Double-tap zoom (a navigating finger's double tap): toggles between the
/// "home" zoom — the page fit in paged notebooks, 100 % on canvases — and
/// a closer look (the zoom last left this way, else 2×), about the tap.
class DoubleTapZoom {
  DoubleTapZoom({
    required this.viewport,
    required this.animator,
    required this.home,
    this.homeOffsetX,
  });

  final ViewportController viewport;
  final ViewportAnimator animator;

  /// The home zoom for the current view (e.g. the fit of the current page).
  final double? Function() home;

  /// The horizontal offset the home zoom uses (pages are centred), if any.
  final double? Function()? homeOffsetX;

  /// How much closer than home the first double tap zooms.
  static const double zoomFactor = 2;

  /// Zooms within this ratio of home count as "at home".
  static const double tolerance = 1.05;

  /// The zoom last left by double-tapping back home.
  double? _last;

  /// Toggles the zoom about [screen].
  void toggle(Offset screen) {
    final base = home();
    if (base == null || viewport.size.isEmpty) return;
    final scale = viewport.scale;
    final atHome = scale / base < tolerance && base / scale < tolerance;
    if (atHome) {
      final last = _last;
      final target = last != null && last > base * tolerance ? last : base * zoomFactor;
      animator.zoomTo(target, focal: screen);
      return;
    }
    if (scale > base) _last = scale;
    final world = viewport.toWorld(screen);
    final x = homeOffsetX?.call() ?? screen.dx - world.dx * base;
    animator.animateTo(scale: base, offset: Offset(x, screen.dy - world.dy * base), anchor: screen);
  }
}
