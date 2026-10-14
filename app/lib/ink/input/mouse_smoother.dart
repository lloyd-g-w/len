import 'dart:math' as math;
import 'dart:ui';

/// Takes the whole-pixel steps out of a mouse's path before it becomes
/// ink (screen pixels and milliseconds, fed as the mouse moves).
///
/// A stylus reports positions to a fraction of a pixel; a mouse (on the
/// web and desktops) to whole pixels, so its path is a staircase with
/// ±0.5 px of error at every sample. At 100 % a pen 2.5 px wide hides it;
/// zoomed out the pen is a fraction of a pixel wide on screen and the
/// steps show as squiggles (and zoomed back in, they are as many times
/// larger in world units as the zoom was small). The outline's own
/// smoothing works in world units relative to the pen's width (its
/// geometry stays exact that way), so it cannot remove them there.
///
/// So when the pen is thinner on screen than [fullWidth], the path is
/// resampled every [spacing] px and smoothed with a centred Gaussian
/// ([sigmaFor]: up to [maxSigma] px, as much as the outline's smoothing
/// lacks): a point is passed on once the samples [reach] past it are
/// known, so the ink trails the mouse by that much (at most 6 px, as with
/// the stabiliser) and never changes once drawn. The window shrinks
/// symmetrically towards both ends, so the stroke starts and ends exactly
/// where the mouse went down and up. A pen at least [fullWidth] wide on
/// screen (the default pen at 100 % and closer) needs none: the mouse's
/// positions pass on as they come, with no lag and no change of shape.
class MouseSmoother {
  /// [onPoint] receives each smoothed point (screen px) and its time.
  MouseSmoother(this.onPoint);

  final void Function(Offset at, int timeMs) onPoint;

  /// Resampling step (px).
  static const double spacing = 1;

  /// The most smoothing (px), for a pen a hairline on screen: enough to
  /// level the steps of a slanted line.
  static const double maxSigma = 2;

  /// The on-screen pen width (px) whose own outline smoothing levels the
  /// steps.
  static const double fullWidth = 2.5;

  /// The smoothing (px) a pen [width] px wide on screen needs: what the
  /// outline's smoothing (in proportion to the width) lacks of [maxSigma]
  /// (Gaussians compose in quadrature); none from [fullWidth] on.
  static double sigmaFor(double width) {
    final r = (width / fullWidth).clamp(0.0, 1.0);
    return maxSigma * math.sqrt(1 - r * r);
  }

  /// How far (px) the ink trails the mouse with the smoothing [sigma].
  static double reachOf(double sigma) => _kOf(sigma) * spacing;

  /// Smoothing below this (px) is none.
  static const double _minSigma = 0.25;

  static int _kOf(double sigma) => sigma < _minSigma ? 0 : (3 * sigma / spacing).ceil();

  /// Samples on each side of a point its smoothing reaches (0: none).
  int _k = 0;
  List<double> _weights = const [1];

  final List<Offset> _path = [];
  final List<int> _times = [];

  /// Points passed on so far (the first is the mouse-down's, not passed).
  int _emitted = 1;

  /// Distance along the last raw segment to the next resampled point.
  double _carry = spacing;
  Offset _last = Offset.zero;
  int _lastTime = 0;

  /// Starts a stroke at [at] (passed on by the caller as the first point)
  /// with a pen [width] px wide on screen.
  void begin(Offset at, int timeMs, {required double width}) {
    final sigma = sigmaFor(width);
    _k = _kOf(sigma);
    _weights = [for (var i = 0; i <= _k; i++) math.exp(-0.5 * math.pow(i * spacing / sigma, 2))];
    _path
      ..clear()
      ..add(at);
    _times
      ..clear()
      ..add(timeMs);
    _emitted = 1;
    _carry = spacing;
    _last = at;
    _lastTime = timeMs;
  }

  /// The mouse moved to [at].
  void add(Offset at, int timeMs) {
    if (_k == 0) {
      _last = at;
      _lastTime = timeMs;
      return onPoint(at, timeMs);
    }
    final d = (at - _last).distance;
    var along = _carry;
    while (along <= d) {
      final t = along / d;
      _path.add(Offset.lerp(_last, at, t)!);
      _times.add(_lastTime + ((timeMs - _lastTime) * t).round());
      along += spacing;
    }
    _carry = along - d;
    _last = at;
    _lastTime = timeMs;
    _emitUpTo(_path.length - 1 - _k);
  }

  /// The mouse went up at its last position: passes on the rest of the
  /// path, ending there.
  void finish() {
    if (_k == 0 || _path.isEmpty) return;
    if (_path.last != _last) {
      _path.add(_last);
      _times.add(_lastTime);
    }
    _emitUpTo(_path.length - 1);
  }

  void _emitUpTo(int last) {
    final n = _path.length;
    for (; _emitted <= last; _emitted++) {
      final i = _emitted;
      final r = math.min(_k, math.min(i, n - 1 - i));
      var x = 0.0, y = 0.0, w = 0.0;
      for (var j = -r; j <= r; j++) {
        final weight = _weights[j.abs()];
        x += _path[i + j].dx * weight;
        y += _path[i + j].dy * weight;
        w += weight;
      }
      onPoint(Offset(x / w, y / w), _times[i]);
    }
  }
}
