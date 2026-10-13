import 'dart:ui';

/// Whether a one-finger swipe turns the page in single-page flow: a quick
/// flick (even a short one) or a deliberate drag across a good part of the
/// screen, mostly sideways.
abstract final class PageSwipe {
  /// A drag this fraction of the screen width turns the page however slow.
  static const double dragFraction = 0.3;

  /// A flick must travel at least this far (logical pixels)...
  static const double flickDistance = 32;

  /// ...at this average speed (logical pixels per second).
  static const double flickSpeed = 300;

  /// Sideways must be at least this many times the vertical travel.
  static const double sideways = 1.5;

  /// The page to turn to from a swipe of [delta] over [duration] on a
  /// screen [width] wide: +1 (next, swiped left), -1 (previous) or 0.
  static int turn(Offset delta, Duration duration, double width) {
    final dx = delta.dx.abs();
    if (dx < flickDistance || dx < sideways * delta.dy.abs()) return 0;
    final seconds = duration.inMicroseconds / Duration.microsecondsPerSecond;
    final flick = seconds > 0 && dx / seconds >= flickSpeed;
    if (!flick && dx < dragFraction * width) return 0;
    return delta.dx < 0 ? 1 : -1;
  }
}
