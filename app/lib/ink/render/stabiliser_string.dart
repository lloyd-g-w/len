import 'dart:ui';

import '../input/live_ink.dart';

/// The stabiliser's string (`LiveInk.stringFrom` → `stringTo`): while the
/// stabiliser holds the ink back from the pen, a hairline from the ink's
/// tip to the pen and a small ring at the pen, as lazy-brush stabilisers
/// show the string the ink is pulled on. Neutral and two-tone, like the
/// eraser's ring (a Graphite line over a light halo), so it reads on any
/// paper and never as ink; drawn only once the gap is more than
/// [hiddenBelow] screen px, fading in over the next [fadeOver] px, so it
/// fades out as the ink closes up on a resting pen. Live only.
class StabiliserString {
  const StabiliserString._();

  /// Gaps (screen px) up to this show no string: the ink is at the pen.
  static const double hiddenBelow = 2;

  /// Screen px over which the string fades in beyond [hiddenBelow].
  static const double fadeOver = 3;

  /// Radius (screen px) of the ring at the pen.
  static const double ringRadius = 2.5;

  static const Color _line = Color(0xB35A5A5A); // Graphite, 70 %
  static const Color _halo = Color(0x80FFFFFF);

  /// The string's opacity (0..1) for a gap of [gap] screen px.
  static double opacityFor(double gap) {
    final t = ((gap - hiddenBelow) / fadeOver).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  /// Paints [live]'s string, if any, on [canvas] in world coordinates
  /// seen at [scale] (screen px per world unit).
  static void paint(Canvas canvas, LiveInk live, double scale) {
    final from = live.stringFrom, to = live.stringTo;
    if (from == null || to == null || live.straightened) return;
    final opacity = opacityFor((to - from).distance * scale);
    if (opacity <= 0) return;
    final px = 1 / scale;
    final halo = Paint()
      ..color = _halo.withValues(alpha: _halo.a * opacity)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.5 * px;
    final line = Paint()
      ..color = _line.withValues(alpha: _line.a * opacity)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = px;
    // The line stops at the ring.
    final d = to - from;
    final long = d.distance * scale > ringRadius;
    final end = long ? to - d / d.distance * (ringRadius * px) : from;
    if (long) canvas.drawLine(from, end, halo);
    canvas.drawCircle(to, ringRadius * px, halo);
    if (long) canvas.drawLine(from, end, line);
    canvas.drawCircle(to, ringRadius * px, line);
  }
}
