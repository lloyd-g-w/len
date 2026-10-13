import 'dart:ui';

import '../../ink/navigation/viewport_animator.dart';
import '../../ink/viewport.dart';

/// Double-tap zoom (a navigating finger's double tap): toggles between the
/// "home" zoom — the page fit in paged notebooks, 100 % on canvases — and
/// a closer look (the zoom last left this way, else 2×), about the tap.
/// A pinch that ends close to home [snap]s to it.
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

  /// A pinch ending within this ratio of home settles exactly at home.
  static const double snapRange = 1.08;

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
    _goHome(screen, base);
  }

  /// After a pinch ending about [focal]: a zoom close to home (but not at
  /// it) glides to home. Returns whether it does.
  bool snap(Offset focal) {
    final base = home();
    if (base == null || viewport.size.isEmpty) return false;
    final ratio = viewport.scale / base;
    if (ratio > snapRange || ratio < 1 / snapRange || (ratio - 1).abs() < 1e-6) return false;
    _goHome(focal, base);
    return true;
  }

  void _goHome(Offset screen, double base) {
    final world = viewport.toWorld(screen);
    final x = homeOffsetX?.call() ?? screen.dx - world.dx * base;
    animator.animateTo(scale: base, offset: Offset(x, screen.dy - world.dy * base), anchor: screen);
  }
}
